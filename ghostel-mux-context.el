;;; ghostel-mux-context.el --- Explicit Bash context -*- lexical-binding: t; -*-
;; Version: 0.4.0
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Explicit activation, passive prompt reports and fresh replies for actions.
;; No remote files or connection wrappers.  See docs/context-awareness.md.
;;; Code:
(require 'ghostel-mux)
(require 'tramp)
(require 'compile)
(require 'shell)
(defgroup ghostel-mux-context nil "Explicit shell context." :group 'ghostel-mux)
(defcustom ghostel-mux-context-timeout 6 "Seconds to wait for a shell response."
  :type 'number :group 'ghostel-mux-context)
(defvar ghostel-mux-context-route-history nil)
(defconst ghostel-mux-context--directory (file-name-directory (or load-file-name buffer-file-name)))
(defconst ghostel-mux-context--blocked "/ghostel-mux-context-unavailable:/")
(defvar ghostel-mux-context--executing nil)
(defvar ghostel-mux-context--sending nil)
(defvar-local ghostel-mux-context--records nil)
(defvar-local ghostel-mux-context--current nil)
(defvar-local ghostel-mux-context--awaiting nil)
(defvar-local ghostel-mux-context--request nil)
(defvar-local ghostel-mux-context--response nil)
(defvar-local ghostel-mux-context--state nil)
(defvar-local ghostel-mux-context--error nil)
(defvar-local ghostel-mux-context--saved nil)
(defvar ghostel-mux-context-mode)
(defun ghostel-mux-context--nonce ()
  "Correlation identifier, not an authentication credential."
  (substring (secure-hash 'sha256 (format "%S:%s:%s" (current-time) (random) (buffer-name))) 0 32))
(defun ghostel-mux-context--block (&optional reason)
  (setq ghostel-mux-context--state 'pending ghostel-mux-context--error reason
        default-directory ghostel-mux-context--blocked list-buffers-directory nil)
  (force-mode-line-update))
(defun ghostel-mux-context--file-handler (operation &rest args)
  "Stop operations on an unavailable context."
  (cond ((eq operation 'file-remote-p) ghostel-mux-context--blocked)
        ((memq operation '(expand-file-name file-name-as-directory directory-file-name))
         (let ((inhibit-file-name-handlers
                (cons #'ghostel-mux-context--file-handler inhibit-file-name-handlers))
               (inhibit-file-name-operation operation)) (apply operation args)))
        (t (user-error "Mux context unavailable; return to an integrated prompt or use C-b i"))))
(add-to-list 'file-name-handler-alist
             (cons (concat "^" (regexp-quote ghostel-mux-context--blocked))
                   #'ghostel-mux-context--file-handler))
(defun ghostel-mux-context--route (input)
  "Parse INPUT without connecting or registering proxies; preserve every hop."
  (setq input (string-trim input))
  (if (string-empty-p input) ""
    (when (string-match-p "[\0\n\r]" input) (user-error "Invalid TRAMP route"))
    (let* ((vec (tramp-dissect-file-name input t)) (method (tramp-file-name-method vec)))
      (unless (and method (assoc method tramp-methods))
        (user-error "Use an explicit configured TRAMP method"))
      (substring input 0 (- (length input) (length (tramp-file-name-localname vec)))))))
(defun ghostel-mux-context--decode (hex)
  (unless (and (stringp hex) (<= (length hex) 16384) (= 0 (% (length hex) 2))
               (not (string-match-p "[^0-9a-f]" hex))) (error "Invalid context field"))
  (let* ((bytes (apply #'unibyte-string
                      (cl-loop for i from 0 below (length hex) by 2
                               collect (string-to-number (substring hex i (+ i 2)) 16))))
         (value (decode-coding-string bytes 'utf-8-unix)))
    (unless (and (equal bytes (encode-coding-string value 'utf-8-unix))
                 (not (string-match-p "\0" value))) (error "Invalid UTF-8 context"))
    value))
(defun ghostel-mux-context--digits-p (s)
  (and (not (string-empty-p s)) (not (string-match-p "[^0-9]" s))))
(defun ghostel-mux-context--check (record host user uid pid cwd)
  (unless (and (not (string-empty-p host)) (not (string-empty-p user))
               (ghostel-mux-context--digits-p uid) (ghostel-mux-context--digits-p pid)
               (string-prefix-p "/" cwd)) (error "Invalid shell identity or directory"))
  (when (and (plist-get record :identity)
             (not (equal (plist-get record :identity) (list host user uid pid))))
    (error "Shell identity changed; activate this shell again"))
  (let ((route (plist-get record :route)))
    (if (string-empty-p route)
        (unless (and (ghostel--local-host-p host) (equal uid (number-to-string (user-uid))))
          (error "This shell needs a TRAMP route including any sudo step"))
      (let* ((v (tramp-dissect-file-name route t)) (expected (or (tramp-file-name-user v) "root")))
        (when (and (member (tramp-file-name-method v) '("sudo" "su" "doas"))
                   (not (equal expected user)))
          (error "Route user %s differs from shell user %s" expected user))))))
(defun ghostel-mux-context--receive (&rest fields)
  "Data-only callback: no IO or evaluation.  Never signal through the VT parser."
  (when (and ghostel-mux-context-mode ghostel-mux--pane)
    (condition-case err
        (progn
          (unless (= (length fields) 10) (error "Invalid context record"))
          (let* ((d (mapcar #'ghostel-mux-context--decode fields))
                 (kind (nth 1 d)) (token (nth 2 d)) (seq (nth 3 d)) (nonce (nth 4 d))
                 (host (nth 5 d)) (user (nth 6 d)) (uid (nth 7 d)) (pid (nth 8 d)) (cwd (nth 9 d))
                 (record (gethash token ghostel-mux-context--records)))
            (when (and record (equal (car d) "1") (member kind '("prompt" "reply"))
                       (ghostel-mux-context--digits-p seq)
                       (> (string-to-number seq) (plist-get record :seq))
                       (or (null ghostel-mux-context--awaiting) (equal token ghostel-mux-context--awaiting))
                       (or (equal kind "prompt") (equal (cons token nonce) ghostel-mux-context--request)))
              (ghostel-mux-context--check record host user uid pid cwd)
              (setq record (plist-put record :seq (string-to-number seq))
                    record (plist-put record :identity (list host user uid pid))
                    record (plist-put record :cwd cwd))
              (let* ((prefix (plist-get record :route))
                     (dir (if (string-suffix-p "/" cwd) cwd (concat cwd "/")))
                     (path (if (string-empty-p prefix) (file-name-quote dir) (concat prefix dir))))
                (puthash token record ghostel-mux-context--records)
                (setq ghostel-mux-context--current token ghostel-mux-context--awaiting nil
                      ghostel-mux-context--state 'ready ghostel-mux-context--error nil
                      default-directory path list-buffers-directory path)
                (when (equal kind "reply") (setq ghostel-mux-context--response path))
                (force-mode-line-update)))))
      (error (ghostel-mux-context--block (error-message-string err))))))
(defun ghostel-mux-context--input (&rest _)
  (when (and ghostel-mux-context-mode (not ghostel-mux-context--sending)
             (not ghostel-mux--suppress-input)) (ghostel-mux-context--block)))
(defun ghostel-mux-context--directory-advice (original &rest args)
  (unless ghostel-mux-context-mode (apply original args)))
(defun ghostel-mux-context--wait (predicate &optional owner)
  (let ((buffer (or owner (current-buffer))) (end (+ (float-time) ghostel-mux-context-timeout)))
    (while (and (buffer-live-p buffer)
                (not (with-current-buffer buffer (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.025))
    (unless (and (buffer-live-p buffer) (with-current-buffer buffer (funcall predicate)))
      (user-error "No context response; use C-b i at an empty interactive Bash prompt"))))
(defun ghostel-mux-context--send (text)
  (let ((ghostel-mux--input-source nil) (ghostel-mux--suppress-input t)
        (ghostel-mux-context--sending t)) (ghostel-send-string text)))
(defun ghostel-mux-context--script (token key)
  (let ((s (with-temp-buffer
             (insert-file-contents (expand-file-name "shell/ghostel-mux-context.bash"
                                                    ghostel-mux-context--directory))
             (buffer-string))))
    (setq s (string-replace "@TOKEN@" token s) s (string-replace "@KEY@" key s)
          s (string-replace "\\" "\\\\" s) s (string-replace "'" "\\'" s)
          s (string-replace "\n" "\\n" s) s (string-replace "\r" "\\r" s))
    (concat " if test -n \"$BASH_VERSION\"; then builtin eval -- $'" s
            "'; else printf 'Mux context requires Bash.\\n'; fi\n")))
;;;###autoload
(defun ghostel-mux-context-enable (route)
  "Activate at an EMPTY interactive Bash prompt and explicitly associate ROUTE.
A TRAMP prefix or full path is accepted; empty means local access."
  (interactive (list (completing-read
                      "Current shell's TRAMP prefix (empty = local; empty Bash prompt required): "
                      ghostel-mux-context-route-history nil nil nil 'ghostel-mux-context-route-history)))
  (ghostel-mux--require-pane)
  (when (or (frame-parameter nil 'ghostel-mux-preview)
            (not (memq ghostel--input-mode '(semi-char char))))
    (user-error "Activate from the live terminal at an empty Bash prompt"))
  (let* ((buffer (current-buffer)) (prefix (ghostel-mux-context--route route)) (token (ghostel-mux-context--nonce))
         (key (number-to-string (string-to-number (substring token 0 12) 16)))
         (script (ghostel-mux-context--script token key)))
    (unless ghostel-mux-context-mode (ghostel-mux-context-mode 1))
    (puthash token (list :route prefix :key key :seq 0) ghostel-mux-context--records)
    (setq ghostel-mux-context--awaiting token)
    (ghostel-mux-context--block)
    (ghostel-mux-context--send script)
    (ghostel-mux-context--wait (lambda () (or ghostel-mux-context--error
                                            (equal token ghostel-mux-context--current))) buffer)
    (when ghostel-mux-context--error (user-error "%s" ghostel-mux-context--error))
    (message "Mux context: %s — C-j opens Dired" (ghostel-mux-context--label))))
(defun ghostel-mux-context--verify ()
  "Require a fresh reply for this action, never just a cached snapshot."
  (ghostel-mux--require-pane)
  (unless (and ghostel-mux-context-mode (eq ghostel-mux-context--state 'ready)
               (not ghostel-mux-context--awaiting) (not (frame-parameter nil 'ghostel-mux-preview)))
    (user-error "Context unavailable; return to an integrated prompt or use C-b i"))
  (let* ((buffer (current-buffer)) (token ghostel-mux-context--current)
         (record (gethash token ghostel-mux-context--records)) (nonce (ghostel-mux-context--nonce))
         (ghostel-mux-context--request (cons token nonce)) (ghostel-mux-context--response nil) ok)
    (unwind-protect
        (progn
          (ghostel-mux-context--send (concat "\e[99;" (plist-get record :key) "~" nonce))
          (ghostel-mux-context--wait (lambda () ghostel-mux-context--response) buffer)
          (setq ok t)
          ghostel-mux-context--response)
      (when (and (not ok) (buffer-live-p buffer))
        (with-current-buffer buffer
          (ghostel-mux-context--block "Fresh context check did not complete"))))))
;;;###autoload
(defun ghostel-mux-context-dired ()
  "Verify the current shell and open Dired at its location."
  (interactive)
  (let ((directory (ghostel-mux-context--verify)) (ghostel-mux-context--executing t))
    (dired directory)))
(defun ghostel-mux-context--command-advice (original &rest args)
  (if (or (not ghostel-mux-context-mode) ghostel-mux-context--executing)
      (apply original args)
    (let* ((default-directory (ghostel-mux-context--verify)) (ghostel-mux-context--executing t)
           (label (ghostel-mux-context--label))
           (identity (substring (secure-hash 'sha256 default-directory) 0 8))
           (compilation-buffer-name-function
            (lambda (mode) (format "*mux-%s:%s:%s*" (downcase mode) label identity))))
      (apply original args))))
(defun ghostel-mux-context--shell-advice (original &optional buffer)
  (if (or (not ghostel-mux-context-mode) ghostel-mux-context--executing) (funcall original buffer)
    (let ((default-directory (ghostel-mux-context--verify)) (ghostel-mux-context--executing t))
      (when (and buffer (get-buffer buffer)) (user-error "Use a new shell buffer for this context"))
      (funcall original (or buffer (generate-new-buffer-name
                                   (format "*mux-shell:%s*" (ghostel-mux-context--label))))))))
(defun ghostel-mux-context--label ()
  (when ghostel-mux-context-mode
    (if (not (eq ghostel-mux-context--state 'ready)) "CTX?"
      (let ((id (plist-get (gethash ghostel-mux-context--current ghostel-mux-context--records) :identity)))
        (format "%s@%s" (nth 1 id) (car id))))))
;;;###autoload
(defun ghostel-mux-context-describe ()
  "Show observed identity, exact route and availability."
  (interactive)
  (ghostel-mux--require-pane)
  (let* ((record (and ghostel-mux-context--records
                      (gethash ghostel-mux-context--current ghostel-mux-context--records)))
         (id (plist-get record :identity)) (state ghostel-mux-context--state)
         (reason ghostel-mux-context--error))
    (with-help-window "*Ghostel Mux Context*"
      (princ (format "Context: %s\nHost: %s\nUser: %s (uid %s)\nShell PID: %s\nDirectory: %s\nTRAMP prefix: %s\n"
                     (or state "not activated") (car id) (nth 1 id) (nth 2 id) (nth 3 id)
                     (plist-get record :cwd) (or (plist-get record :route) "not assigned")))
      (when reason (princ (format "\n%s\n" reason)))
      (princ "\nC-b i: activate at an empty Bash prompt; enter the exact TRAMP prefix.\nC-j: Dired with a fresh reply. M-x compile/shell/shell-command/async-shell-command also verify.\nNew SSH/sudo shells need activation. Integrated parents resume on exit.\n"))))
(defvar ghostel-mux-context-mode-map
  (let ((map (make-sparse-keymap))) (define-key map (kbd "C-j") #'ghostel-mux-context-dired) map))
(defvar ghostel-mux-context--maps (list (cons 'ghostel-mux-context-mode ghostel-mux-context-mode-map)))
(add-to-list 'emulation-mode-map-alists 'ghostel-mux-context--maps)
(define-minor-mode ghostel-mux-context-mode
  "Explicit context in this pane. Activate through C-b i.
Disabling restores the previous directory; shell hooks remain until exit."
  :lighter nil :keymap ghostel-mux-context-mode-map
  (if ghostel-mux-context-mode
      (progn
        (ghostel-mux--require-pane)
        (setq ghostel-mux-context--saved
              (list default-directory ghostel-eval-cmds (local-variable-p 'ghostel-eval-cmds))
              ghostel-mux-context--records (make-hash-table :test #'equal))
        (setq-local ghostel-eval-cmds (cons '("ghostel-mux-context" ghostel-mux-context--receive)
                                          (copy-sequence ghostel-eval-cmds)))
        (ghostel-mux-context--block))
    (setq default-directory (or (car ghostel-mux-context--saved) default-directory)
          list-buffers-directory default-directory
          ghostel-mux-context--state nil ghostel-mux-context--current nil
          ghostel-mux-context--awaiting nil ghostel-mux-context--records nil)
    (if (nth 2 ghostel-mux-context--saved)
        (setq-local ghostel-eval-cmds (nth 1 ghostel-mux-context--saved))
      (kill-local-variable 'ghostel-eval-cmds))))
(dolist (fn '(ghostel--send-encoded ghostel--send-string ghostel--paste-text ghostel--write-pty))
  (advice-add fn :before #'ghostel-mux-context--input))
(advice-add 'ghostel--update-directory :around #'ghostel-mux-context--directory-advice)
(dolist (fn '(compile shell-command async-shell-command))
  (advice-add fn :around #'ghostel-mux-context--command-advice))
(advice-add 'shell :around #'ghostel-mux-context--shell-advice)
(defun ghostel-mux-context-unload-function ()
  (dolist (buf (buffer-list))
    (with-current-buffer buf (when ghostel-mux-context-mode (ghostel-mux-context-mode -1))))
  (dolist (fn '(ghostel--send-encoded ghostel--send-string ghostel--paste-text ghostel--write-pty))
    (advice-remove fn #'ghostel-mux-context--input))
  (advice-remove 'ghostel--update-directory #'ghostel-mux-context--directory-advice)
  (dolist (fn '(compile shell-command async-shell-command))
    (advice-remove fn #'ghostel-mux-context--command-advice))
  (advice-remove 'shell #'ghostel-mux-context--shell-advice)
  (setq emulation-mode-map-alists (delq 'ghostel-mux-context--maps emulation-mode-map-alists)
        file-name-handler-alist
        (cl-remove #'ghostel-mux-context--file-handler file-name-handler-alist :key #'cdr))
  nil)
(provide 'ghostel-mux-context)
;;; ghostel-mux-context.el ends here
