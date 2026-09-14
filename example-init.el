;;; example-init.el --- Install and configure Ghostel Mux -*- lexical-binding: t; -*-

;; Prerequisites: Git and a working Ghostel installation (M-x ghostel).
(use-package ghostel-mux
  :ensure nil
  :load-path "~/.emacs.d/lisp/ghostel-mux/"
  :commands (ghostel-mux)
  :bind ("C-c m" . ghostel-mux)
  :init
  ;; Clone once, directly into the requested directory.
  ;; An existing installation is kept; updates are explicit git pull operations.
  (let* ((dir (expand-file-name "~/.emacs.d/lisp/ghostel-mux/"))
         (source (expand-file-name "ghostel-mux.el" dir)))
    (unless (file-exists-p source)
      (when (file-exists-p (directory-file-name dir))
        (error "Ghostel Mux: %s exists but ghostel-mux.el is missing" dir))
      (unless (executable-find "git")
        (error "Ghostel Mux: install Git and restart Emacs"))
      (make-directory (file-name-directory (directory-file-name dir)) t)
      (let ((stage (make-temp-file
                    (expand-file-name ".ghostel-mux-install-"
                                      (file-name-directory (directory-file-name dir))) t)))
        (unwind-protect
            (progn
              (unless (zerop (process-file
                             "git" nil "*Ghostel Mux install*" nil "clone" "--"
                             "https://github.com/SweatierKey/ghostel-mux.git" stage))
                (error "Ghostel Mux: clone failed; see *Ghostel Mux install*"))
              (unless (file-exists-p (expand-file-name "ghostel-mux.el" stage))
                (error "Ghostel Mux: incomplete checkout"))
              (rename-file stage (directory-file-name dir)))
          (when (file-directory-p stage) (delete-directory stage t))))))
  (setq ghostel-mux-directory (expand-file-name "~")
        ghostel-mux-scrollback-bytes (* 50 1024 1024)
        ghostel-mux-log-output t))

;; Optional settings (defaults shown):
;; (setq ghostel-mux-session-colors t
;;       ghostel-mux-auto-tile t
;;       ghostel-mux-tree-preview t
;;       ghostel-mux-session-preview t
;;       ghostel-mux-window-preview t
;;       ghostel-mux-pane-preview t)
;;
;; C-b S creates a session immediately; C-b $ renames it.
;; C-b b: tree, with SPC preview, R rename, m move, M-up/down reorder.
;; C-b B: ALL terminal buffers. C-b w: windows of the attached session.
;; C-b P: panes of the current window. C-b y: visible panes SYNC only.
;; C-b g: Ghostel's original C-c map, including mode switching.
;; Set ghostel-mux-log-output to nil for Ghostel's native PTY backend.
;;; example-init.el ends here
