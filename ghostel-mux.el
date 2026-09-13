;;; ghostel-mux.el --- Tmux-style workspaces for Ghostel -*- lexical-binding: t; -*-

;; Version: 0.2.0
;; Package-Requires: ((emacs "29.1") (ghostel "0.40.0"))
;; Keywords: terminals, convenience
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; M-x ghostel-mux starts or selects a session.  C-b is a buffer-local
;; prefix.  Sessions contain windows (layouts), which contain terminal
;; panes (buffers).  See README.md for installation and the key table.
;; Internal Ghostel integration is isolated in the adapter at the end.
;; There is no daemon, remote agent, persistent process restoration, or
;; dependency on Perspective.  Unmanaged Ghostel buffers are unaffected.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'face-remap)
(require 'windmove)
(require 'ghostel)
(declare-function consult--read "consult" (table &rest options))
(defvar consult-preview-key)

(defgroup ghostel-mux nil "Terminal multiplexing inside Emacs." :group 'ghostel)
(defcustom ghostel-mux-prefix-key (kbd "C-b")
  "Prefix in managed terminal buffers.  Set before loading this package."
  :type 'key-sequence)
(defcustom ghostel-mux-scrollback-bytes (* 50 1024 1024)
  "Scrollback budget of each new pane, in bytes, not lines."
  :type 'integer)
(defcustom ghostel-mux-log-output t
  "Record raw terminal output for new panes.
Logging selects Ghostel's Emacs PTY backend for those panes only."
  :type 'boolean)
(defcustom ghostel-mux-log-directory
  (expand-file-name "ghostel-mux-logs/" user-emacs-directory)
  "Local directory for per-pane raw output recordings."
  :type 'directory)
(defcustom ghostel-mux-log-flush-interval 1
  "Seconds between flushing output recordings to disk."
  :type 'number)
(defcustom ghostel-mux-status-interval 5
  "Seconds between status clock updates."
  :type 'number)
(defcustom ghostel-mux-confirm-kill t
  "Ask before explicitly closing panes or windows with terminal processes."
  :type 'boolean)
(defcustom ghostel-mux-directory nil
  "Starting directory for new sessions, or nil to use the current directory.
Existing windows remember their initial directory.  Splits use that directory
so an SSH prompt's OSC 7 directory never starts an unexpected TRAMP session."
  :type '(choice (const nil) directory))
(defcustom ghostel-mux-session-preview t
  "Preview session layouts with Consult when it is available.
Uses `consult-preview-key'.  Without Consult, use normal completion."
  :type 'boolean)
(defcustom ghostel-mux-window-preview t
  "Preview Mux window layouts with Consult in `ghostel-mux-select-window'.
Uses `consult-preview-key'.  Without Consult, use normal completion."
  :type 'boolean)
(defcustom ghostel-mux-pane-preview t
  "Preview terminal buffers with Consult in `ghostel-mux-select-pane'.
Uses `consult-preview-key'; nil keeps the ordinary completion selector."
  :type 'boolean)
(defcustom ghostel-mux-session-colors t
  "Color only the owning session name in each pane's header.
Session colors identify ownership, independently of selection, SYNC and COPY.
Set to nil to use the surrounding theme's text color everywhere."
  :type 'boolean)
(defvar ghostel-mux-session-history nil)
(defvar ghostel-mux-window-history nil)
(defvar ghostel-mux-pane-history nil)

(defface ghostel-mux-normal '((t (:inherit mode-line)))
  "Normal status." :group 'ghostel-mux)
(defface ghostel-mux-sync '((t (:inherit mode-line :weight bold :underline t)))
  "Broadcast status." :group 'ghostel-mux)
(defface ghostel-mux-prefix '((t (:inherit mode-line :weight bold :box t)))
  "Pending prefix status." :group 'ghostel-mux)
(defface ghostel-mux-active '((t (:inherit header-line :weight bold)))
  "Active pane title." :group 'ghostel-mux)
(defface ghostel-mux-inactive '((t (:inherit default)))
  "Legacy face; Mux no longer remaps terminal colors." :group 'ghostel-mux)
(defface ghostel-mux-terminal '((t (:inherit default)))
  "Legacy face; Mux no longer remaps terminal colors." :group 'ghostel-mux)
(defface ghostel-mux-copy '((t (:weight bold :underline t)))
  "Copy mode indicator, using the surrounding theme colors." :group 'ghostel-mux)
(defface ghostel-mux-broadcast-marker '((t (:weight bold :underline t)))
  "Compact broadcast marker, independent of the session accent."
  :group 'ghostel-mux)

(defface ghostel-mux-session-blue
  '((((class color) (min-colors 89) (background dark)) (:foreground "#91b7d0"))
    (((class color) (min-colors 89) (background light)) (:foreground "#005f87"))
    (t ()))
  "Blue session accent; never changes the background." :group 'ghostel-mux)
(defface ghostel-mux-session-green
  '((((class color) (min-colors 89) (background dark)) (:foreground "#a0bf93"))
    (((class color) (min-colors 89) (background light)) (:foreground "#5f875f"))
    (t ()))
  "Green session accent." :group 'ghostel-mux)
(defface ghostel-mux-session-violet
  '((((class color) (min-colors 89) (background dark)) (:foreground "#b6a0cc"))
    (((class color) (min-colors 89) (background light)) (:foreground "#875f87"))
    (t ()))
  "Violet session accent." :group 'ghostel-mux)
(defface ghostel-mux-session-sand
  '((((class color) (min-colors 89) (background dark)) (:foreground "#d0b482"))
    (((class color) (min-colors 89) (background light)) (:foreground "#875f00"))
    (t ()))
  "Sand session accent." :group 'ghostel-mux)
(defface ghostel-mux-session-teal
  '((((class color) (min-colors 89) (background dark)) (:foreground "#86bfba"))
    (((class color) (min-colors 89) (background light)) (:foreground "#008787"))
    (t ()))
  "Teal session accent." :group 'ghostel-mux)
(defface ghostel-mux-session-rose
  '((((class color) (min-colors 89) (background dark)) (:foreground "#cc9fac"))
    (((class color) (min-colors 89) (background light)) (:foreground "#af5f87"))
    (t ()))
  "Rose session accent." :group 'ghostel-mux)
(defface ghostel-mux-session-slate
  '((((class color) (min-colors 89) (background dark)) (:foreground "#87afff"))
    (((class color) (min-colors 89) (background light)) (:foreground "#5f5faf"))
    (t ()))
  "Slate session accent." :group 'ghostel-mux)
(defface ghostel-mux-session-clay
  '((((class color) (min-colors 89) (background dark)) (:foreground "#d7875f"))
    (((class color) (min-colors 89) (background light)) (:foreground "#875f5f"))
    (t ()))
  "Clay session accent." :group 'ghostel-mux)

(defcustom ghostel-mux-session-color-faces
  '(ghostel-mux-session-blue ghostel-mux-session-green
    ghostel-mux-session-violet ghostel-mux-session-sand
    ghostel-mux-session-teal ghostel-mux-session-rose
    ghostel-mux-session-slate ghostel-mux-session-clay)
  "Palette for session names, in allocation order.
New sessions take the least used face among open sessions.  Existing sessions
keep their face across rename, switching, preview and source reload, unless
that face is removed from this list.  Customize these faces for your theme.
Use foreground-only faces to preserve the header's other attributes.
An empty palette disables accents.  Built-in accents require 89 colors."
  :type '(repeat face))

;; `defface' does not update already loaded defaults.  Migrate the old
;; hardcoded defaults on live reload, preserving theme and Custom specs.
(dolist (entry '((ghostel-mux-normal :inherit mode-line)
                 (ghostel-mux-sync :inherit mode-line :weight bold :underline t)
                 (ghostel-mux-prefix :inherit mode-line :weight bold :box t)
                 (ghostel-mux-active :inherit header-line :weight bold)
                 (ghostel-mux-inactive :inherit default)
                 (ghostel-mux-terminal :inherit default)))
  (let* ((face (car entry))
         (attrs (cadar (get face 'face-defface-spec))))
    (when (or (plist-get attrs :background) (plist-get attrs :foreground))
      (face-spec-set face (list (list t (cdr entry))) 'face-defface-spec))))

(cl-defstruct (ghostel-mux--session (:constructor ghostel-mux--make-session))
  id name windows current previous directory frame)
(cl-defstruct (ghostel-mux--window (:constructor ghostel-mux--make-window))
  id name session panes state zoom-state zoom-pane active previous sync directory)
(cl-defstruct (ghostel-mux--pane (:constructor ghostel-mux--make-pane))
  id buffer window label log-file log-chunks (log-bytes 0) log-error)

(defvar ghostel-mux--sessions nil)
(defvar ghostel-mux--serial 0)
(defvar ghostel-mux--session-counters (make-hash-table :test #'eq :weakness 'key))
(defvar ghostel-mux--session-color-table (make-hash-table :test #'eq :weakness 'key))
(defvar ghostel-mux--creating-number nil)
(defvar-local ghostel-mux--session-number nil)
(defvar ghostel-mux--timer nil)
(defvar ghostel-mux--last-clock 0)
(defvar ghostel-mux--installed nil)
(defvar ghostel-mux--restoring nil)
(defvar ghostel-mux--closing nil)
(defvar ghostel-mux--creating-pane nil)
(defvar ghostel-mux--input-source nil)
(defvar ghostel-mux--dispatching nil)
(defvar ghostel-mux--suppress-input nil)
(defvar ghostel-mux--rendering-selected 'outside)
(defvar ghostel-mux--rendering-source-window nil)
(defvar-local ghostel-mux--pane nil)
(defvar-local ghostel-mux--copy-active nil)
(defvar-local ghostel-mux--terminal-active nil)
(defvar-local ghostel-mux--face-cookie nil)
(defvar-local ghostel-mux--face-state nil)
(defvar-local ghostel-mux--saved-presentation nil)

(defun ghostel-mux--id () (cl-incf ghostel-mux--serial))
(defun ghostel-mux--session-color (s)
  "Return S's stable accent face, allocating a free or least used one."
  (let* ((palette (seq-filter #'facep ghostel-mux-session-color-faces))
         (old (gethash s ghostel-mux--session-color-table)))
    (if (memq old palette) old
      (let (best count)
        (dolist (face palette)
          (let ((used (cl-count face ghostel-mux--sessions
                                :key (lambda (other)
                                       (gethash other ghostel-mux--session-color-table)))))
            (when (or (null count) (< used count))
              (setq best face count used))))
        (when best (puthash s best ghostel-mux--session-color-table))
        best))))
(defun ghostel-mux--next-session-number (s)
  "Allocate a display number in S, independently of internal IDs."
  (let ((n (1+ (gethash s ghostel-mux--session-counters 0))))
    (puthash s n ghostel-mux--session-counters)
    n))

(defun ghostel-mux--rename-session-buffers (s)
  "Name S's terminal buffers using their session-local numbers."
  ;; Creation order frees old global-number names before later panes need them.
  (dolist (p (sort (cl-loop for w in (ghostel-mux--session-windows s)
                            append (copy-sequence (ghostel-mux--window-panes w)))
                   (lambda (a b) (< (ghostel-mux--pane-id a) (ghostel-mux--pane-id b)))))
    (when (buffer-live-p (ghostel-mux--pane-buffer p))
      (with-current-buffer (ghostel-mux--pane-buffer p)
        (when ghostel-mux--session-number
          (rename-buffer (format "*mux:%s:%d*" (ghostel-mux--session-name s)
                                 ghostel-mux--session-number) t))))))

(defun ghostel-mux--migrate-session-numbers ()
  "Assign numbers to pre-0.1.5 panes without changing their IDs or logs."
  (dolist (s ghostel-mux--sessions)
    (let ((panes (sort (cl-loop for w in (ghostel-mux--session-windows s)
                                append (copy-sequence (ghostel-mux--window-panes w)))
                       (lambda (a b) (< (ghostel-mux--pane-id a) (ghostel-mux--pane-id b))))))
      (dolist (p panes)
        (when (buffer-live-p (ghostel-mux--pane-buffer p))
          (with-current-buffer (ghostel-mux--pane-buffer p)
            (unless ghostel-mux--session-number
              (setq ghostel-mux--session-number (ghostel-mux--next-session-number s))))))
      (ghostel-mux--rename-session-buffers s))))

(defun ghostel-mux--group-name (w)
  "Return W's session name and window number, or detached for nil."
  (if w (format "%s:%d" (ghostel-mux--session-name (ghostel-mux--window-session w))
                (ghostel-mux--window-number w))
    "detached"))

(defun ghostel-mux--buffer-number (p)
  "Return P's session-local buffer number."
  (or (buffer-local-value 'ghostel-mux--session-number (ghostel-mux--pane-buffer p)) 0))
(defun ghostel-mux--current-session ()
  (frame-parameter nil 'ghostel-mux-session))
(defun ghostel-mux--current-window ()
  (when-let ((s (ghostel-mux--current-session)))
    (ghostel-mux--session-current s)))
(defun ghostel-mux--require-window ()
  (or (ghostel-mux--current-window) (user-error "No attached mux session")))
(defun ghostel-mux--require-pane ()
  (or ghostel-mux--pane (user-error "Select a Ghostel mux pane first")))
(defun ghostel-mux--pane-live-p (p)
  (and (buffer-live-p (ghostel-mux--pane-buffer p))
       (with-current-buffer (ghostel-mux--pane-buffer p)
         (and ghostel--term (process-live-p ghostel--process)))))
(defun ghostel-mux--all-panes ()
  (cl-loop for s in ghostel-mux--sessions append
           (cl-loop for w in (ghostel-mux--session-windows s)
                    append (ghostel-mux--window-panes w))))
(defun ghostel-mux--window-number (w)
  (1+ (or (cl-position w (ghostel-mux--session-windows
                         (ghostel-mux--window-session w))) 0)))
(defun ghostel-mux--pane-number (p)
  (1+ (or (cl-position p (ghostel-mux--window-panes
                         (ghostel-mux--pane-window p))) 0)))
(defun ghostel-mux--pane-title (p)
  (or (ghostel-mux--pane-label p)
      (and (buffer-live-p (ghostel-mux--pane-buffer p))
           (with-current-buffer (ghostel-mux--pane-buffer p)
             (cond ((boundp 'ghostel-title) (symbol-value 'ghostel-title))
                   ((boundp 'ghostel--title) (symbol-value 'ghostel--title)))))
      "shell"))
(defun ghostel-mux--window-title (w)
  (or (ghostel-mux--window-name w)
      (when-let ((p (or (ghostel-mux--window-active w)
                       (car (ghostel-mux--window-panes w)))))
        (ghostel-mux--pane-title p)) "empty"))
(defun ghostel-mux--name (prompt &optional initial)
  (let ((s (string-trim (read-string prompt initial))))
    (when (string-empty-p s) (user-error "Name cannot be empty")) s))

;;; Workspace ownership and automatic layouts
(defcustom ghostel-mux-auto-tile t
  "Automatically tile after pane creation or removal.
Each window can override this with `ghostel-mux-toggle-auto-tile'.
Manual resizing lasts until the next pane topology change."
  :type 'boolean :group 'ghostel-mux)
;; External tables keep existing struct instances valid on live reload.
(defvar ghostel-mux--auto-tiles (make-hash-table :test #'eq :weakness 'key))
(defvar ghostel-mux--layouts (make-hash-table :test #'eq :weakness 'key))
(defvar ghostel-mux--dirty-layouts (make-hash-table :test #'eq :weakness 'key))

(defun ghostel-mux--auto-tile-p (w)
  (gethash w ghostel-mux--auto-tiles ghostel-mux-auto-tile))
(defun ghostel-mux--tree-active-p (&optional frame)
  (eq (window-buffer (frame-selected-window frame)) (get-buffer "*Ghostel Mux Tree*")))
(defun ghostel-mux--known-window-p (w)
  (and (ghostel-mux--window-p w)
       (memq (ghostel-mux--window-session w) ghostel-mux--sessions)
       (memq w (ghostel-mux--session-windows (ghostel-mux--window-session w)))))

(defun ghostel-mux--build-layout (w panes &optional frame)
  "Build and validate a tiled state without changing W or its ownership.
Use FRAME's dimensions.  No shell is created or destroyed."
  (when panes
    (with-selected-frame (or frame (selected-frame))
      (save-window-excursion
        (let ((ghostel-mux--restoring t))
          (delete-other-windows)
          (ghostel-mux--tile (selected-window) panes (gethash w ghostel-mux--layouts "tiled"))
          (balance-windows)
          (dolist (win (window-list nil 'no-minibuffer))
            (set-window-parameter win 'ghostel-mux-pane-id
                                  (ghostel-mux--pane-id
                                   (buffer-local-value 'ghostel-mux--pane (window-buffer win)))))
          (window-state-get (frame-root-window)))))))

(defun ghostel-mux--apply-pending-layout (w)
  "Rebuild dirty geometry once W is displayed, deferring while zoomed."
  (when (and (gethash w ghostel-mux--dirty-layouts)
             (not (ghostel-mux--window-zoom-state w)))
    (condition-case err
        (progn
          (setf (ghostel-mux--window-state w)
                (ghostel-mux--build-layout w (ghostel-mux--window-panes w)))
          (remhash w ghostel-mux--dirty-layouts))
      (error
       ;; Keep the last valid layout and all shells if the frame is too small.
       (setf (ghostel-mux--window-sync w) nil)
       (message "Mux tiling deferred (SYNC OFF): %s" (error-message-string err))))))

(defun ghostel-mux-toggle-auto-tile (&optional window)
  "Toggle automatic tiling for WINDOW, or the active Mux window."
  (interactive)
  (let* ((w (or window (ghostel-mux--require-window)))
         (on (not (ghostel-mux--auto-tile-p w))))
    (puthash w on ghostel-mux--auto-tiles)
    (if on (puthash w t ghostel-mux--dirty-layouts)
      (remhash w ghostel-mux--dirty-layouts))
    (unless (ghostel-mux--tree-active-p)
      (when (eq w (ghostel-mux--current-window)) (ghostel-mux--restore w)))
    (ghostel-mux--refresh)
    (message "%s: AUTO TILE %s" (ghostel-mux--group-name w) (if on "ON" "OFF"))))

(defun ghostel-mux--auto-split ()
  "Create a pane without requiring space in the selected leaf window."
  (let* ((w (ghostel-mux--require-window))
         (ps (ghostel-mux--window-panes w)) (pane nil))
    ;; Preflight the extra leaf with a live existing buffer before spawning.
    (ghostel-mux--build-layout w (append ps (list (car ps))))
    (condition-case err
        (let* ((p (setq pane (ghostel-mux--new-pane w)))
               (panes (append ps (list p)))
               (state (ghostel-mux--build-layout w panes)))
          (setf (ghostel-mux--window-panes w) panes
                (ghostel-mux--window-state w) state
                (ghostel-mux--window-zoom-state w) nil
                (ghostel-mux--window-zoom-pane w) nil
                (ghostel-mux--window-active w) p)
          (remhash w ghostel-mux--dirty-layouts)
          (ghostel-mux--restore w))
      ((error quit)
       (when (and pane (not (memq pane (ghostel-mux--window-panes w)))
                  (buffer-live-p (ghostel-mux--pane-buffer pane)))
         (let ((ghostel-mux--closing t) (ghostel-query-before-killing nil))
           (kill-buffer (ghostel-mux--pane-buffer pane))))
       (signal (car err) (cdr err))))))

(defun ghostel-mux--read-destination (pane)
  "Choose a destination session or window for PANE."
  (let (choices)
    (dolist (s ghostel-mux--sessions)
      (push (cons (format "%s / [new window]" (ghostel-mux--session-name s)) s) choices)
      (dolist (w (ghostel-mux--session-windows s))
        (unless (eq w (ghostel-mux--pane-window pane))
          (push (cons (format "%s / %d: %s" (ghostel-mux--session-name s)
                              (ghostel-mux--window-number w) (ghostel-mux--window-title w)) w) choices))))
    (cdr (assoc (completing-read "Move pane to: " (nreverse choices) nil t) choices))))

(defun ghostel-mux--read-target-session (source)
  (let ((choices (mapcar (lambda (s) (cons (ghostel-mux--session-name s) s))
                        (delq source (copy-sequence ghostel-mux--sessions)))))
    (unless choices (user-error "Create another session first"))
    (cdr (assoc (completing-read "Move window to session: " choices nil t) choices))))

(defun ghostel-mux--prepare-move (sessions)
  "Validate affected frames and capture their current layouts before moving."
  (when (active-minibuffer-window) (user-error "Finish the minibuffer before moving"))
  (dolist (s (delete-dups (copy-sequence sessions)))
    (unless (memq s ghostel-mux--sessions) (user-error "Session no longer exists"))
    (when-let ((f (ghostel-mux--session-frame s)))
      (when (frame-live-p f)
        (when (or (frame-parameter f 'ghostel-mux-preview) (active-minibuffer-window))
          (user-error "Finish selection in the affected frame first"))
        (with-selected-frame f (ghostel-mux--capture))))))

(defun ghostel-mux--prune-window (w)
  "Remove empty W and repair session navigation references."
  (let ((s (ghostel-mux--window-session w)))
    (unless (ghostel-mux--window-panes w)
      (setf (ghostel-mux--session-windows s) (delq w (ghostel-mux--session-windows s))))
    (unless (memq (ghostel-mux--session-current s) (ghostel-mux--session-windows s))
      (setf (ghostel-mux--session-current s) (car (ghostel-mux--session-windows s))))
    (unless (memq (ghostel-mux--session-previous s) (ghostel-mux--session-windows s))
      (setf (ghostel-mux--session-previous s) nil))))

(defun ghostel-mux--finish-move (sessions)
  "Restore affected attached layouts, removing sessions left empty."
  (dolist (s (delete-dups (copy-sequence sessions)))
    (let ((f (ghostel-mux--session-frame s)))
      (if (ghostel-mux--session-windows s)
          (when (and f (frame-live-p f) (not (ghostel-mux--tree-active-p f)))
            (with-selected-frame f
              (ghostel-mux--restore (ghostel-mux--session-current s))))
        (when (and f (frame-live-p f))
          (with-selected-frame f
            (if (ghostel-mux--tree-active-p)
                (set-frame-parameter f 'ghostel-mux-session nil)
              (let ((ghostel-mux--restoring t)) (ghostel-mux-detach)))))
        (setf (ghostel-mux--session-frame s) nil)
        (setq ghostel-mux--sessions (delq s ghostel-mux--sessions)))))
  (ghostel-mux--refresh))

(defun ghostel-mux-move-pane (destination &optional pane)
  "Move PANE to DESTINATION without restarting its process.
DESTINATION is a window, or a session in which to create a new window.
Interactive use follows the moved pane; the tree stays open when used there.
Both affected windows have SYNC disabled.  Their pane layouts are rebuilt."
  (interactive (list (ghostel-mux--read-destination (ghostel-mux--require-pane))))
  (let* ((p (or pane (ghostel-mux--require-pane)))
         (source (ghostel-mux--pane-window p))
         (s1 (ghostel-mux--window-session source))
         (new (ghostel-mux--session-p destination))
         (s2 (if new destination (and (ghostel-mux--window-p destination)
                                      (ghostel-mux--window-session destination))))
         (tree (ghostel-mux--tree-active-p)))
    (unless (and (ghostel-mux--known-window-p source) (ghostel-mux--pane-live-p p)
                 (memq p (ghostel-mux--window-panes source))
                 (or new (ghostel-mux--known-window-p destination)))
      (user-error "Source or destination is no longer available"))
    (when (eq source destination) (user-error "Pane already belongs to this window"))
    (ghostel-mux--prepare-move (list s1 s2))
    (let* ((target (if new (ghostel-mux--make-window :id (ghostel-mux--id) :session s2
                                                    :directory (ghostel-mux--session-directory s2)) destination))
           (from (delq p (copy-sequence (ghostel-mux--window-panes source))))
           (to (append (ghostel-mux--window-panes target) (list p)))
           ;; All geometry is validated before changing the ownership graph.
           (from-state (ghostel-mux--build-layout source from (ghostel-mux--session-frame s1)))
           (to-state (ghostel-mux--build-layout target to (ghostel-mux--session-frame s2))))
      (setf (ghostel-mux--window-panes source) from
            (ghostel-mux--window-panes target) to
            (ghostel-mux--pane-window p) target)
      (when new
        (setf (ghostel-mux--session-windows s2) (append (ghostel-mux--session-windows s2) (list target))))
      (setf (ghostel-mux--window-active target) p)
      (dolist (w (list source target))
        (setf (ghostel-mux--window-sync w) nil
              (ghostel-mux--window-zoom-state w) nil
              (ghostel-mux--window-zoom-pane w) nil
              (ghostel-mux--window-previous w) nil)
        (unless (memq (ghostel-mux--window-active w) (ghostel-mux--window-panes w))
          (setf (ghostel-mux--window-active w) (car (ghostel-mux--window-panes w))))
        (remhash w ghostel-mux--dirty-layouts))
      (setf (ghostel-mux--window-state source) from-state
            (ghostel-mux--window-state target) to-state)
      (unless (eq s1 s2)
        (with-current-buffer (ghostel-mux--pane-buffer p)
          (setq ghostel-mux--session-number (ghostel-mux--next-session-number s2)))
        (ghostel-mux--rename-session-buffers s2))
      (ghostel-mux--prune-window source)
      (ghostel-mux--finish-move (list s1 s2))
      (unless tree (ghostel-mux--select-pane p))
      (message "Pane moved to %s; affected windows SYNC OFF" (ghostel-mux--group-name target))
      p)))

(defun ghostel-mux--validate-window-transfer (w destination)
  "Check W's normal and zoom layouts in DESTINATION's frame before moving."
  (with-selected-frame (or (ghostel-mux--session-frame destination) (selected-frame))
    (save-window-excursion
      (let ((ghostel-mux--restoring t))
        (dolist (state (list (ghostel-mux--window-state w)
                            (ghostel-mux--window-zoom-state w)))
          (when state
            (delete-other-windows)
            (window-state-put state (frame-root-window) 'safe)))))))

(defun ghostel-mux-move-window (destination &optional window)
  "Move WINDOW and all its live panes to session DESTINATION.
Keep processes, logs, layout and zoom.  Disable this window's SYNC."
  (interactive (list (ghostel-mux--read-target-session (ghostel-mux--current-session))))
  (let* ((w (or window (ghostel-mux--require-window)))
         (source (ghostel-mux--window-session w))
         (tree (ghostel-mux--tree-active-p)))
    (unless (ghostel-mux--known-window-p w) (user-error "Window no longer exists"))
    (when (eq source destination) (user-error "Window already belongs to this session"))
    (ghostel-mux--prepare-move (list source destination))
    (ghostel-mux--validate-window-transfer w destination)
    (setf (ghostel-mux--session-windows source) (delq w (ghostel-mux--session-windows source))
          (ghostel-mux--session-windows destination)
          (append (ghostel-mux--session-windows destination) (list w))
          (ghostel-mux--window-session w) destination
          (ghostel-mux--window-sync w) nil)
    ;; Prune navigation in the old parent after the reparenting.
    (unless (memq (ghostel-mux--session-current source) (ghostel-mux--session-windows source))
      (setf (ghostel-mux--session-current source) (car (ghostel-mux--session-windows source))))
    (when (eq (ghostel-mux--session-previous source) w)
      (setf (ghostel-mux--session-previous source) nil))
    (dolist (p (ghostel-mux--window-panes w))
      (with-current-buffer (ghostel-mux--pane-buffer p)
        (setq ghostel-mux--session-number (ghostel-mux--next-session-number destination))))
    (ghostel-mux--rename-session-buffers destination)
    (ghostel-mux--finish-move (list source destination))
    (unless tree (ghostel-mux--switch-window w))
    (message "Window moved to %s; SYNC OFF" (ghostel-mux--group-name w))
    w))

;;; Workspace tree
(defvar-local ghostel-mux--tree-folded nil)
(defvar ghostel-mux-tree-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'ghostel-mux-tree-visit)
    (define-key map (kbd "TAB") #'ghostel-mux-tree-toggle)
    (define-key map (kbd "m") #'ghostel-mux-tree-move)
    (define-key map (kbd "a") #'ghostel-mux-tree-auto-tile)
    (define-key map (kbd "g") #'ghostel-mux-tree-refresh)
    (define-key map (kbd "q") #'ghostel-mux-tree-quit)
    (define-key map (kbd "n") #'next-line)
    (define-key map (kbd "p") #'previous-line)
    map))
(define-derived-mode ghostel-mux-tree-mode special-mode "Mux Tree"
  "Browse and reparent live sessions, windows and panes."
  (setq-local truncate-lines t))

(defun ghostel-mux--tree-node ()
  (or (get-text-property (line-beginning-position) 'ghostel-mux-node)
      (user-error "Select a session, window or pane row")))
(defun ghostel-mux--tree-row (object text &optional face)
  (insert (propertize (concat text "\n") 'ghostel-mux-node object 'face face)))
(defun ghostel-mux-tree-refresh ()
  "Refresh the ownership tree, retaining selection and collapsed branches."
  (interactive)
  (let ((node (get-text-property (line-beginning-position) 'ghostel-mux-node))
        (line (line-number-at-pos)) (inhibit-read-only t))
    (erase-buffer)
    (insert "GHOSTEL MUX — SESSIONS / WINDOWS / PANES\n"
            "RET visit · TAB fold · m move · a auto tile · g refresh · q return\n\n")
    (dolist (s ghostel-mux--sessions)
      (ghostel-mux--tree-row s (format "%s %s" (if (memq s ghostel-mux--tree-folded) "+" "−")
                                       (ghostel-mux--session-name s))
                            (and ghostel-mux-session-colors (ghostel-mux--session-color s)))
      (unless (memq s ghostel-mux--tree-folded)
        (dolist (w (ghostel-mux--session-windows s))
          (ghostel-mux--tree-row w
           (format "  %s %d: %s  [%s%s%s]" (if (memq w ghostel-mux--tree-folded) "+" "−")
                   (ghostel-mux--window-number w) (ghostel-mux--window-title w)
                   (if (ghostel-mux--auto-tile-p w) "AUTO TILE" "MANUAL")
                   (if (ghostel-mux--window-sync w) " · SYNC enabled" " · SYNC off")
                   (if (ghostel-mux--window-zoom-state w) " · ZOOM" "")) 'bold)
          (unless (memq w ghostel-mux--tree-folded)
            (dolist (p (ghostel-mux--window-panes w))
              (ghostel-mux--tree-row p
               (format "      P%d / B%d  %s  %s" (ghostel-mux--pane-number p)
                       (ghostel-mux--buffer-number p) (ghostel-mux--pane-title p)
                       (if (ghostel-mux--pane-live-p p) "" "[EXIT]"))))))))
    (goto-char (or (and node (text-property-any (point-min) (point-max) 'ghostel-mux-node node))
                   (point-min)))
    (unless node (forward-line (max 3 (1- line))))
    (set-buffer-modified-p nil)))

(defun ghostel-mux-tree ()
  "Show the live ownership tree in this frame, keeping the terminal layout."
  (interactive)
  (let ((node (or ghostel-mux--pane (ghostel-mux--current-window))))
    (unless (ghostel-mux--tree-active-p)
      (ghostel-mux--capture)
      (set-frame-parameter nil 'ghostel-mux-tree-return (current-window-configuration))
      (let ((ghostel-mux--restoring t))
        (delete-other-windows)
        (switch-to-buffer (get-buffer-create "*Ghostel Mux Tree*"))
        (unless (derived-mode-p 'ghostel-mux-tree-mode) (ghostel-mux-tree-mode)))
      (let* ((w (if (ghostel-mux--pane-p node) (ghostel-mux--pane-window node) node))
             (s (and w (ghostel-mux--window-session w))))
        (setq ghostel-mux--tree-folded (delq s (delq w ghostel-mux--tree-folded)))))
    (ghostel-mux-tree-refresh)
    (when-let ((pos (and node (text-property-any (point-min) (point-max) 'ghostel-mux-node node))))
      (goto-char pos))))

(defun ghostel-mux-tree-toggle ()
  (interactive)
  (let ((node (ghostel-mux--tree-node)))
    (when (or (ghostel-mux--session-p node) (ghostel-mux--window-p node))
      (if (memq node ghostel-mux--tree-folded)
          (setq ghostel-mux--tree-folded (delq node ghostel-mux--tree-folded))
        (push node ghostel-mux--tree-folded))
      (ghostel-mux-tree-refresh))))
(defun ghostel-mux-tree-quit ()
  (interactive)
  (let ((config (frame-parameter nil 'ghostel-mux-tree-return))
        (s (ghostel-mux--current-session)) (ghostel-mux--restoring t))
    (set-frame-parameter nil 'ghostel-mux-tree-return nil)
    (cond ((and (memq s ghostel-mux--sessions) (ghostel-mux--session-current s))
           (ghostel-mux--restore (ghostel-mux--session-current s)))
          (config (set-window-configuration config))
          (t (switch-to-buffer (get-buffer-create "*scratch*"))))))
(defun ghostel-mux-tree-visit ()
  (interactive)
  (let ((node (ghostel-mux--tree-node))
        (return-state (frame-parameter nil 'ghostel-mux-return-state))
        (ghostel-mux--restoring t))
    (cond ((and (ghostel-mux--pane-p node) (memq node (ghostel-mux--all-panes)))
           (ghostel-mux--attach (ghostel-mux--window-session (ghostel-mux--pane-window node))
                                (ghostel-mux--pane-window node))
           (ghostel-mux--select-pane node))
          ((ghostel-mux--known-window-p node) (ghostel-mux--switch-window node))
          ((memq node ghostel-mux--sessions) (ghostel-mux--attach node))
          (t (user-error "Entry no longer exists; refresh the tree")))
    (when return-state (set-frame-parameter nil 'ghostel-mux-return-state return-state))
    (set-frame-parameter nil 'ghostel-mux-tree-return nil)))
(defun ghostel-mux-tree-move ()
  (interactive)
  (let ((node (ghostel-mux--tree-node)))
    (cond ((ghostel-mux--pane-p node)
           (ghostel-mux-move-pane (ghostel-mux--read-destination node) node))
          ((ghostel-mux--window-p node)
           (ghostel-mux-move-window
            (ghostel-mux--read-target-session (ghostel-mux--window-session node)) node))
          (t (user-error "Select a pane or window to move")))))
(defun ghostel-mux-tree-auto-tile ()
  (interactive)
  (let* ((node (ghostel-mux--tree-node))
         (w (if (ghostel-mux--pane-p node) (ghostel-mux--pane-window node) node)))
    (unless (ghostel-mux--known-window-p w) (user-error "Select a window or pane"))
    (ghostel-mux-toggle-auto-tile w)))

;;; Layout ownership
(defun ghostel-mux--capture ()
  "Capture the attached layout, keeping the unzoomed state separately."
  (unless (or ghostel-mux--restoring (ghostel-mux--tree-active-p)
              (frame-parameter nil 'ghostel-mux-preview))
    (when-let ((w (ghostel-mux--current-window)))
      (dolist (win (window-list))
        (let ((p (buffer-local-value 'ghostel-mux--pane (window-buffer win))))
          (set-window-parameter win 'ghostel-mux-pane-id (and p (ghostel-mux--pane-id p)))))
      (setf (ghostel-mux--window-state w) (window-state-get (frame-root-window)))
      (when (and ghostel-mux--pane
                 (eq w (ghostel-mux--pane-window ghostel-mux--pane)))
        (setf (ghostel-mux--window-active w) ghostel-mux--pane)))))

(defun ghostel-mux--restore (w)
  "Restore W's layout in the current frame."
  (ghostel-mux--apply-pending-layout w)
  (let ((ghostel-mux--restoring t))
    (delete-other-windows)
    (let ((state (ghostel-mux--window-state w))
          (fallback (ghostel-mux--pane-buffer (car (ghostel-mux--window-panes w)))))
      (when state
        (window-state-put (ghostel-mux--sanitize-state state fallback)
                          (frame-root-window) 'safe)))
    ;; Remove windows resurrected by window-state-put with dead pane buffers.
    (dolist (win (window-list))
      (when (and (window-parameter win 'ghostel-mux-pane-id)
                 (not (memq (window-parameter win 'ghostel-mux-pane-id)
                            (mapcar #'ghostel-mux--pane-id (ghostel-mux--window-panes w)))))
        (if (one-window-p t)
            (when-let ((p (car (ghostel-mux--window-panes w))))
              (set-window-buffer win (ghostel-mux--pane-buffer p)))
          (delete-window win))))
    (when-let* ((p (or (ghostel-mux--window-zoom-pane w)
                      (ghostel-mux--window-active w)
                      (car (ghostel-mux--window-panes w))))
                (buf (ghostel-mux--pane-buffer p)))
      (when (buffer-live-p buf)
        (if-let ((win (get-buffer-window buf)))
            (select-window win)
          (set-window-buffer (selected-window) buf))))
    (set-buffer (window-buffer (selected-window))))
  (ghostel-mux--refresh))

(defun ghostel-mux--sanitize-state (state fallback)
  "Replace dead buffer objects in saved STATE before Emacs restores it."
  (cond ((bufferp state) (if (buffer-live-p state) state fallback))
        ((markerp state) (or (marker-position state) 1))
        ((consp state) (cons (ghostel-mux--sanitize-state (car state) fallback)
                            (ghostel-mux--sanitize-state (cdr state) fallback)))
        (t state)))

(defun ghostel-mux--attach (s &optional w)
  "Attach S and W, moving ownership from another frame if necessary."
  (ghostel-mux--capture)
  (when-let ((owner (ghostel-mux--session-frame s)))
    (when (and (frame-live-p owner) (not (eq owner (selected-frame))))
      (with-selected-frame owner (ghostel-mux-detach))))
  (unless (ghostel-mux--current-session)
    (set-frame-parameter nil 'ghostel-mux-return-state
                         (window-state-get (frame-root-window))))
  (when-let ((old (ghostel-mux--current-session)))
    (unless (eq old s) (setf (ghostel-mux--session-frame old) nil)))
  (set-frame-parameter nil 'ghostel-mux-session s)
  (setf (ghostel-mux--session-frame s) (selected-frame))
  (when w (setf (ghostel-mux--session-current s) w))
  (ghostel-mux--restore (ghostel-mux--session-current s)))

;;;###autoload
(defun ghostel-mux (&optional name)
  "Select an existing session or create NAME."
  (interactive)
  (ghostel-mux--install)
  (let* ((names (mapcar #'ghostel-mux--session-name ghostel-mux--sessions))
         (name (or name (if names (ghostel-mux--read-session "Session (new name creates): " nil)
                         (read-string "New session: " "main"))))
         (s (cl-find name ghostel-mux--sessions :key #'ghostel-mux--session-name
                     :test #'equal)))
    (if s (ghostel-mux--attach s) (ghostel-mux-new-session name))))

;;;###autoload
(defun ghostel-mux-new-session (name)
  "Create NAME with one window and one fresh terminal."
  (interactive (list (ghostel-mux--name "New session: ")))
  (ghostel-mux--install)
  (when (or (string-empty-p (string-trim name))
            (cl-find name ghostel-mux--sessions :key #'ghostel-mux--session-name
                     :test #'equal))
    (user-error "Session name is empty or already exists: %s" name))
  (let* ((dir (file-name-as-directory
               (expand-file-name (or ghostel-mux-directory default-directory))))
         (s (ghostel-mux--make-session :id (ghostel-mux--id) :name name :directory dir))
         (w (ghostel-mux--make-window :id (ghostel-mux--id) :session s :directory dir))
         (p (ghostel-mux--new-pane w)))
    (setf (ghostel-mux--window-panes w) (list p)
          (ghostel-mux--window-active w) p
          (ghostel-mux--session-windows s) (list w)
          (ghostel-mux--session-current s) w)
    (ghostel-mux--session-color s)
    (setq ghostel-mux--sessions (append ghostel-mux--sessions (list s)))
    (ghostel-mux--attach s w) s))

(defun ghostel-mux--session-named (name)
  "Return the current session object matching NAME."
  (cl-find name ghostel-mux--sessions :key #'ghostel-mux--session-name :test #'equal))

(defun ghostel-mux--session-annotation (name)
  "Describe NAME without changing or attaching its session."
  (when-let* ((s (ghostel-mux--session-named name))
              (w (ghostel-mux--session-current s)))
    (format "  [%d windows · %d panes%s%s%s]"
            (length (ghostel-mux--session-windows s))
            (length (ghostel-mux--window-panes w))
            (if (ghostel-mux--window-zoom-state w) " · ZOOM" "")
            (if (ghostel-mux--window-sync w) " · SYNC enabled" " · SYNC off")
            (if (and (ghostel-mux--session-frame s)
                     (not (eq (ghostel-mux--session-frame s) (selected-frame))))
                " · other frame, no preview" ""))))

(defun ghostel-mux--preview-restore (original)
  "Restore ORIGINAL without replacing the active completion minibuffer."
  (let* ((mini (active-minibuffer-window))
         (buffer (and mini (window-buffer mini)))
         (height (and mini (window-total-height mini))))
    (set-window-configuration original)
    (when (and mini (window-live-p mini) (buffer-live-p buffer))
      (set-window-buffer mini buffer)
      (let ((delta (- height (window-total-height mini))))
        (unless (zerop delta)
          (ignore-errors (window-resize mini delta)))))))

(defun ghostel-mux--session-preview-state (frame original &optional resolve-window)
  "Make a Consult state function for FRAME, restoring ORIGINAL on reset.
Display only: never attach a session or capture a preview as its layout.
RESOLVE-WINDOW maps a candidate to its window; nil uses session names."
  (lambda (action name)
    (when (and (frame-live-p frame) (memq action '(preview exit)))
      (let ((ghostel-mux--restoring t))
        (ghostel-mux--preview-restore original)
        (when-let* ((w (and (eq action 'preview) name
                           (if resolve-window (funcall resolve-window name)
                             (when-let ((s (ghostel-mux--session-named name)))
                               (ghostel-mux--session-current s)))))
                    (s (ghostel-mux--window-session w))
                    (p (cl-find-if #'ghostel-mux--pane-live-p (ghostel-mux--window-panes w))))
          ;; Do not resize or take a session away from another frame to preview it.
          (unless (and (ghostel-mux--session-frame s)
                       (not (eq frame (ghostel-mux--session-frame s))))
            ;; Keep Consult's original window alive as the first layout leaf.
            (with-selected-window (frame-selected-window frame)
              (delete-other-windows)
              (if-let ((state (ghostel-mux--window-state w)))
                  (window-state-put
                   (ghostel-mux--sanitize-state state (ghostel-mux--pane-buffer p))
                   (frame-root-window frame) 'safe)
                (set-window-buffer (selected-window) (ghostel-mux--pane-buffer p)))))))
      (force-mode-line-update t))))

(defun ghostel-mux--pane-preview-state (frame original resolve-pane)
  "Preview the buffer returned by RESOLVE-PANE, preserving ORIGINAL in FRAME."
  (lambda (action name)
    (when (and (frame-live-p frame) (memq action '(preview exit)))
      (let ((ghostel-mux--restoring t))
        (ghostel-mux--preview-restore original)
        (when-let* ((p (and (eq action 'preview) name (funcall resolve-pane name)))
                    (live (ghostel-mux--pane-live-p p)))
          ;; Replace only the original input pane; leave sibling views intact.
          (set-window-buffer (frame-selected-window frame) (ghostel-mux--pane-buffer p))))
      (force-mode-line-update t))))

(defun ghostel-mux--read-with-preview (names prompt require-match category history
                                             &optional resolve-window annotate resolve-pane)
  "Read NAMES with guarded layout preview and unconditional restoration.
PROMPT, REQUIRE-MATCH, CATEGORY and HISTORY are Consult options.
RESOLVE-WINDOW and ANNOTATE map candidates to windows and descriptions.
When RESOLVE-PANE is non-nil, preview its buffer instead of a full layout."
  (ghostel-mux--capture)
  (let* ((frame (selected-frame))
         (session (ghostel-mux--current-session))
         (original (current-window-configuration frame))
         ;; This selector restores layouts, not a search landing position.
         ;; Avoid Ghostel treating restored point as a jump into scrollback.
         (minibuffer-exit-hook
          (remq 'ghostel--minibuffer-exit-maybe-leave (copy-sequence minibuffer-exit-hook)))
         name)
    (unwind-protect
        (progn
          (set-frame-parameter frame 'ghostel-mux-preview t)
          (setq name
                (consult--read names :prompt prompt :require-match require-match
                               :category category :sort nil
                               :history history
                               :annotate annotate
                               :preview-key consult-preview-key
                               :state (if resolve-pane
                                          (ghostel-mux--pane-preview-state frame original resolve-pane)
                                        (ghostel-mux--session-preview-state frame original resolve-window)))))
      (when (frame-live-p frame)
        (set-frame-parameter frame 'ghostel-mux-preview nil)
        (let ((ghostel-mux--restoring t)) (set-window-configuration original))
        (when (frame-parameter frame 'ghostel-mux-preview-reconcile)
          (set-frame-parameter frame 'ghostel-mux-preview-reconcile nil)
          (when session (ghostel-mux--reconcile session)))
        (ghostel-mux--refresh)))
    name))

(defun ghostel-mux--read-session (prompt require-match)
  "Read a session name with PROMPT and REQUIRE-MATCH, optionally previewing."
  (let* ((names (mapcar #'ghostel-mux--session-name ghostel-mux--sessions))
         (name (if (and ghostel-mux-session-preview (require 'consult nil t))
                   (ghostel-mux--read-with-preview
                    names prompt require-match 'ghostel-mux-session
                    'ghostel-mux-session-history nil #'ghostel-mux--session-annotation)
                 (completing-read prompt names nil require-match nil 'ghostel-mux-session-history))))
    (when (and (member name names) (not (ghostel-mux--session-named name)))
      (user-error "Session exited during selection: %s" name))
    name))

(defun ghostel-mux-select-session ()
  "Choose from open sessions, previewing layouts when Consult is available."
  (interactive)
  (unless ghostel-mux--sessions (user-error "No mux sessions"))
  (let ((s (ghostel-mux--session-named (ghostel-mux--read-session "Session: " t))))
    (unless s (user-error "Session is no longer available"))
    (ghostel-mux--attach s)))

(defun ghostel-mux-detach ()
  "Leave the mux layout and restore the previous Emacs workspace."
  (interactive)
  (ghostel-mux--capture)
  (when-let ((s (ghostel-mux--current-session)))
    (setf (ghostel-mux--session-frame s) nil)
    (set-frame-parameter nil 'ghostel-mux-session nil)
    (let ((state (frame-parameter nil 'ghostel-mux-return-state))
          (ghostel-mux--restoring t))
      (when state
        (delete-other-windows)
        (window-state-put state (frame-root-window) 'safe)))
    (set-frame-parameter nil 'ghostel-mux-return-state nil)
    (set-buffer (window-buffer (selected-window)))
    (ghostel-mux--refresh)))

(defun ghostel-mux-rename-session (name)
  "Rename the attached session to NAME."
  (interactive (list (ghostel-mux--name "Session name: ")))
  (let ((s (or (ghostel-mux--current-session) (user-error "No session"))))
    (when (cl-find-if (lambda (other)
                       (and (not (eq s other))
                            (equal name (ghostel-mux--session-name other))))
                     ghostel-mux--sessions)
      (user-error "Session already exists"))
    (setf (ghostel-mux--session-name s) name)
    (ghostel-mux--rename-session-buffers s)
    (ghostel-mux--refresh)))

(defun ghostel-mux-new-window ()
  "Create a window in the current session."
  (interactive)
  (let* ((s (or (ghostel-mux--current-session) (user-error "No session")))
         (w (ghostel-mux--make-window :id (ghostel-mux--id) :session s
                                      :directory (ghostel-mux--session-directory s)))
         (p (ghostel-mux--new-pane w)))
    (setf (ghostel-mux--window-panes w) (list p)
          (ghostel-mux--window-active w) p
          (ghostel-mux--session-windows s)
          (append (ghostel-mux--session-windows s) (list w)))
    (ghostel-mux--switch-window w) w))

(defun ghostel-mux--switch-window (w)
  (ghostel-mux--capture)
  (let ((s (ghostel-mux--window-session w)))
    (unless (eq w (ghostel-mux--session-current s))
      (setf (ghostel-mux--session-previous s) (ghostel-mux--session-current s)))
    (ghostel-mux--attach s w)))

(defun ghostel-mux-select-window ()
  "Choose a window in the attached session, with optional Consult preview."
  (interactive)
  (let* ((s (ghostel-mux--window-session (ghostel-mux--require-window)))
         (prompt (format "Window (%s): " (ghostel-mux--session-name s)))
         (choices
          (cl-loop for w in (ghostel-mux--session-windows s)
                            collect (cons (format "%s:%d  %s%s"
                                                  (ghostel-mux--session-name s)
                                                  (ghostel-mux--window-number w)
                                                  (ghostel-mux--window-title w)
                                                  (if (ghostel-mux--window-sync w) " [SYNC]" "")) w)))
         (name (if (and ghostel-mux-window-preview (require 'consult nil t))
                   (ghostel-mux--read-with-preview
                    (mapcar #'car choices) prompt t 'ghostel-mux-window
                    'ghostel-mux-window-history
                    (lambda (candidate) (cdr (assoc candidate choices))))
                 (completing-read prompt choices nil t nil 'ghostel-mux-window-history)))
         (w (cdr (assoc name choices))))
    (unless (and w
                 (memq (ghostel-mux--window-session w) ghostel-mux--sessions)
                 (memq w (ghostel-mux--session-windows (ghostel-mux--window-session w))))
      (user-error "Window exited during selection: %s" name))
    (ghostel-mux--switch-window w)))

(defun ghostel-mux--cycle-window (delta)
  (let* ((w (ghostel-mux--require-window))
         (windows (ghostel-mux--session-windows (ghostel-mux--window-session w)))
         (index (cl-position w windows)))
    (ghostel-mux--switch-window (nth (mod (+ index delta) (length windows)) windows))))
(defun ghostel-mux-next-window () (interactive) (ghostel-mux--cycle-window 1))
(defun ghostel-mux-previous-window () (interactive) (ghostel-mux--cycle-window -1))
(defun ghostel-mux-last-window ()
  (interactive)
  (let* ((w (ghostel-mux--require-window)) (s (ghostel-mux--window-session w)))
    (if (memq (ghostel-mux--session-previous s) (ghostel-mux--session-windows s))
        (ghostel-mux--switch-window (ghostel-mux--session-previous s))
      (user-error "No previous window"))))
(defun ghostel-mux-window-by-number (n)
  "Select window N, numbered from one."
  (interactive "nWindow number: ")
  (let* ((w (ghostel-mux--require-window))
         (next (and (> n 0) (nth (1- n) (ghostel-mux--session-windows
                                        (ghostel-mux--window-session w))))))
    (unless next (user-error "No window %d" n)) (ghostel-mux--switch-window next)))
(defun ghostel-mux-rename-window (name)
  "Name the current window NAME.  Empty restores automatic naming."
  (interactive "sWindow name (empty = automatic): ")
  (setf (ghostel-mux--window-name (ghostel-mux--require-window))
        (unless (string-empty-p name) name))
  (ghostel-mux--refresh))

;;; Panes and zoom
(defun ghostel-mux--create-terminal (name)
  "Create a new terminal named NAME using the available public Ghostel API.
Older Ghostel exposes only its interactive entry point.  A non-numeric
prefix forces a fresh buffer; the temporary display is restored before
Mux attaches its own layout.  Do not alias private Ghostel constructors."
  (if (fboundp 'ghostel-create)
      (ghostel-create name)
    (let ((ghostel-buffer-name name))
      (save-current-buffer
        (save-window-excursion
          (ghostel '(4)))))))

(defun ghostel-mux--new-pane (w)
  (let* ((s (ghostel-mux--window-session w))
         (ghostel-mux--creating-number (ghostel-mux--next-session-number s))
         (p (ghostel-mux--make-pane :id (ghostel-mux--id) :window w))
         (ghostel-mux--creating-pane p)
         (default-directory (ghostel-mux--window-directory w))
         (ghostel-use-native-pty (and (not ghostel-mux-log-output) ghostel-use-native-pty))
         (ghostel-max-scrollback ghostel-mux-scrollback-bytes)
         (ghostel-kill-buffer-on-exit t)
         (ghostel-mode-hook (append ghostel-mode-hook '(ghostel-mux--setup-pane)))
         (name (format "*mux:%s:%d*"
                       (ghostel-mux--session-name (ghostel-mux--window-session w))
                       ghostel-mux--creating-number)))
    (condition-case err
        (let ((buf (ghostel-mux--create-terminal name)))
          (setf (ghostel-mux--pane-buffer p) buf) p)
      ((error quit)
       (when (buffer-live-p (ghostel-mux--pane-buffer p))
         (let ((ghostel-mux--closing t))
           (kill-buffer (ghostel-mux--pane-buffer p))))
       (signal (car err) (cdr err))))))

(defun ghostel-mux--setup-pane ()
  "Attach identity and logging before Ghostel starts the shell."
  (when ghostel-mux--creating-pane
    (setq-local ghostel-mux--pane ghostel-mux--creating-pane)
    (setq-local ghostel-mux--session-number ghostel-mux--creating-number)
    (setf (ghostel-mux--pane-buffer ghostel-mux--pane) (current-buffer))
    (setq-local ghostel-kill-buffer-on-exit t
                ghostel-readonly-fast-exit nil
                ghostel-mouse-drag-input-mode 'copy)
    (when ghostel-mux-log-output (ghostel-mux--open-log ghostel-mux--pane))
    (ghostel-mux-pane-mode 1)
    (add-hook 'kill-buffer-hook #'ghostel-mux--buffer-killed nil t)))

(defun ghostel-mux--unzoom (w)
  (when (ghostel-mux--window-zoom-state w)
    (setf (ghostel-mux--window-state w) (ghostel-mux--window-zoom-state w)
          (ghostel-mux--window-zoom-state w) nil
          (ghostel-mux--window-zoom-pane w) nil)
    (ghostel-mux--restore w)))

(defun ghostel-mux--manual-split (side)
  (let* ((p (ghostel-mux--require-pane)) (w (ghostel-mux--pane-window p)))
    (unless (eq w (ghostel-mux--current-window)) (user-error "Attach this pane's session first"))
    (ghostel-mux--unzoom w)
    (let* ((old (selected-window)) (new (split-window old nil side)) (pane nil))
      (condition-case err
          (progn
            (select-window new)
            (setq pane (ghostel-mux--new-pane w))
            (setf (ghostel-mux--window-panes w)
                  (append (ghostel-mux--window-panes w) (list pane)))
            (set-window-buffer new (ghostel-mux--pane-buffer pane))
            (set-buffer (ghostel-mux--pane-buffer pane))
            (setf (ghostel-mux--window-active w) pane)
            (ghostel-mux--capture)
            (ghostel-mux--refresh))
        ((error quit)
         (when (window-live-p new) (delete-window new))
         (select-window old)
         (signal (car err) (cdr err)))))))
(defun ghostel-mux--split (side)
  (let* ((p (ghostel-mux--require-pane)) (w (ghostel-mux--pane-window p)))
    (unless (eq w (ghostel-mux--current-window)) (user-error "Attach this pane's session first"))
    (if (ghostel-mux--auto-tile-p w) (ghostel-mux--auto-split)
      (ghostel-mux--manual-split side))))
(defun ghostel-mux-split-right () (interactive) (ghostel-mux--split 'right))
(defun ghostel-mux-split-below () (interactive) (ghostel-mux--split 'below))

(defun ghostel-mux-zoom ()
  "Toggle zoom.  SYNC targets only visible panes, so zoom makes input local."
  (interactive)
  (let* ((p (ghostel-mux--require-pane)) (w (ghostel-mux--pane-window p)))
    (if (ghostel-mux--window-zoom-state w)
        (ghostel-mux--unzoom w)
      (ghostel-mux--capture)
      (setf (ghostel-mux--window-zoom-state w) (ghostel-mux--window-state w)
            (ghostel-mux--window-zoom-pane w) p)
      (delete-other-windows)
      (ghostel-mux--capture))
    (set-buffer (window-buffer (selected-window)))
    (ghostel-mux--refresh)))

(defun ghostel-mux--select-pane (p)
  (let* ((w (ghostel-mux--pane-window p))
         (old (ghostel-mux--window-active w)))
    (unless (eq w (ghostel-mux--current-window)) (ghostel-mux--switch-window w))
    (unless (eq old p) (setf (ghostel-mux--window-previous w) old))
    (setf (ghostel-mux--window-active w) p)
    (if (ghostel-mux--window-zoom-state w)
        (progn
          (set-window-buffer (selected-window) (ghostel-mux--pane-buffer p))
          (setf (ghostel-mux--window-zoom-pane w) p))
      (if-let ((win (get-buffer-window (ghostel-mux--pane-buffer p))))
          (select-window win)
        (set-window-buffer (selected-window) (ghostel-mux--pane-buffer p))))
    (set-buffer (window-buffer (selected-window)))
    (ghostel-mux--refresh)))
(defun ghostel-mux--cycle-pane (delta)
  "Select the pane DELTA positions from the current pane, wrapping around."
  (let* ((p (ghostel-mux--require-pane))
         (ps (ghostel-mux--window-panes (ghostel-mux--pane-window p))))
    (ghostel-mux--select-pane (nth (mod (+ delta (cl-position p ps)) (length ps)) ps))))
(defun ghostel-mux-next-pane ()
  "Select the next pane in this pane's Mux window."
  (interactive) (ghostel-mux--cycle-pane 1))
(defun ghostel-mux-previous-pane ()
  "Select the previous pane in this pane's Mux window."
  (interactive) (ghostel-mux--cycle-pane -1))
(defun ghostel-mux-attach-pane-session ()
  "Activate the selected terminal's owning session and mux window."
  (interactive)
  (ghostel-mux--select-pane (ghostel-mux--require-pane))
  (message "Active group: %s — %s"
           (ghostel-mux--group-name (ghostel-mux--current-window))
           (ghostel-mux--sync-label (ghostel-mux--current-window))))
(defun ghostel-mux-last-pane ()
  (interactive)
  (let* ((w (ghostel-mux--require-window)) (p (ghostel-mux--window-previous w)))
    (unless (memq p (ghostel-mux--window-panes w)) (user-error "No previous pane"))
    (ghostel-mux--select-pane p)))
(defun ghostel-mux-select-pane ()
  "Select a pane in the active Mux window, with optional Consult buffer preview."
  (interactive)
  (let* ((w (ghostel-mux--require-window))
         (choices (mapcar (lambda (p)
                            (cons (format "%d  %s%s" (ghostel-mux--pane-number p)
                                          (ghostel-mux--pane-title p)
                                          (if (ghostel-mux--pane-live-p p) "" " [EXIT]")) p))
                          (ghostel-mux--window-panes w)))
         (prompt (format "Pane (%s): " (ghostel-mux--group-name w)))
         (name (if (and ghostel-mux-pane-preview (require 'consult nil t))
                   (ghostel-mux--read-with-preview
                    (mapcar #'car choices) prompt t 'ghostel-mux-pane
                    'ghostel-mux-pane-history nil nil
                    (lambda (candidate) (cdr (assoc candidate choices))))
                 (completing-read prompt choices nil t nil 'ghostel-mux-pane-history)))
         (p (cdr (assoc name choices))))
    (unless (and p (memq (ghostel-mux--window-session w) ghostel-mux--sessions)
                 (memq w (ghostel-mux--session-windows (ghostel-mux--window-session w)))
                 (memq p (ghostel-mux--window-panes w)) (ghostel-mux--pane-live-p p))
      (user-error "Pane exited during selection: %s" name))
    (ghostel-mux--select-pane p)))
(defun ghostel-mux--move (direction)
  (let ((win (windmove-find-other-window direction)))
    (when (and (window-live-p win)
               (buffer-local-value 'ghostel-mux--pane (window-buffer win)))
      (ghostel-mux--select-pane
       (buffer-local-value 'ghostel-mux--pane (window-buffer win))))))
(defun ghostel-mux-pane-left () (interactive) (ghostel-mux--move 'left))
(defun ghostel-mux-pane-right () (interactive) (ghostel-mux--move 'right))
(defun ghostel-mux-pane-up () (interactive) (ghostel-mux--move 'up))
(defun ghostel-mux-pane-down () (interactive) (ghostel-mux--move 'down))
(defun ghostel-mux-rename-pane (name)
  "Set pane label NAME; empty restores the terminal's OSC title."
  (interactive "sPane label (empty = automatic): ")
  (setf (ghostel-mux--pane-label (ghostel-mux--require-pane))
        (unless (string-empty-p name) name))
  (ghostel-mux--refresh))

(defun ghostel-mux-layout (&optional layout)
  "Choose an evenly divided layout for all panes in this window."
  (interactive)
  (let* ((w (ghostel-mux--require-window))
         (layout (or layout (completing-read "Layout: " '("tiled" "horizontal" "vertical") nil t)))
         (ps (ghostel-mux--window-panes w))
         (saved (window-state-get (frame-root-window))))
    (ghostel-mux--unzoom w)
    (condition-case err
        (progn
          (delete-other-windows)
          (ghostel-mux--tile (selected-window) ps layout)
          (balance-windows)
          (puthash w layout ghostel-mux--layouts)
          (remhash w ghostel-mux--dirty-layouts)
          (ghostel-mux--capture) (ghostel-mux--refresh))
      (error (window-state-put saved (frame-root-window) 'safe)
             (signal (car err) (cdr err))))))

(defun ghostel-mux-next-layout ()
  "Cycle tiled, horizontal and vertical layouts without a prompt."
  (interactive)
  (let* ((old (or (frame-parameter nil 'ghostel-mux-layout-index) -1))
         (next (mod (1+ old) 3))
         (name (nth next '("tiled" "horizontal" "vertical"))))
    (ghostel-mux-layout name)
    (set-frame-parameter nil 'ghostel-mux-layout-index next)
    (message "Layout: %s" name)))

(defun ghostel-mux-layout-tiled ()
  "Arrange all panes in a balanced grid, like tmux's M-5 layout."
  (interactive)
  (ghostel-mux-layout "tiled")
  (set-frame-parameter nil 'ghostel-mux-layout-index 0)
  (message "Layout: tiled"))

(defun ghostel-mux-balance ()
  "Balance pane sizes while keeping the current split arrangement."
  (interactive)
  (ghostel-mux--unzoom (ghostel-mux--require-window))
  (balance-windows)
  (ghostel-mux--capture)
  (ghostel-mux--refresh))

(defun ghostel-mux-display-panes ()
  "Show pane numbers and read a single digit for two seconds."
  (interactive)
  (let* ((w (ghostel-mux--require-window))
         (ps (ghostel-mux--window-panes w))
         (event (read-event
                 (concat (mapconcat (lambda (p) (format "%d:%s" (ghostel-mux--pane-number p)
                                                        (ghostel-mux--pane-title p))) ps "  ")
                         "  — select a number") nil 2)))
    (when (and (integerp event) (>= event ?1) (<= event ?9))
      (when-let ((p (nth (- event ?1) ps))) (ghostel-mux--select-pane p)))))

(defun ghostel-mux-clock ()
  "Show the current date and time in the echo area."
  (interactive) (message "%s" (format-time-string "%H:%M:%S  %d-%b-%Y")))
(defun ghostel-mux--tile (win ps layout)
  (if (null (cdr ps))
      (set-window-buffer win (ghostel-mux--pane-buffer (car ps)))
    (let* ((n (/ (length ps) 2))
           (side (cond ((equal layout "horizontal") 'right)
                       ((equal layout "vertical") 'below)
                       ((> (window-total-width win) (* 2 (window-total-height win))) 'right)
                       (t 'below)))
           (other (split-window win nil side)))
      (ghostel-mux--tile win (seq-take ps n) layout)
      (ghostel-mux--tile other (nthcdr n ps) layout))))

;;; Closing / external buffer death
(defun ghostel-mux--confirm-close (ps description)
  (or (not ghostel-mux-confirm-kill)
      (not (cl-some #'ghostel-mux--pane-live-p ps))
      (yes-or-no-p (concat description " (terminates terminal processes)? "))))
(defun ghostel-mux-kill-pane ()
  (interactive)
  (let ((p (ghostel-mux--require-pane)))
    (when (ghostel-mux--confirm-close (list p) "Close pane")
      (with-current-buffer (ghostel-mux--pane-buffer p)
        (let ((ghostel-query-before-killing nil)) (kill-buffer))))))
(defun ghostel-mux-kill-window ()
  (interactive)
  (let* ((w (ghostel-mux--require-window)) (ps (copy-sequence (ghostel-mux--window-panes w))))
    (when (ghostel-mux--confirm-close ps "Close window")
      (dolist (p ps)
        (when (buffer-live-p (ghostel-mux--pane-buffer p))
          (with-current-buffer (ghostel-mux--pane-buffer p)
            (let ((ghostel-query-before-killing nil)) (kill-buffer))))))))
(defun ghostel-mux-kill-session ()
  (interactive)
  (let* ((s (or (ghostel-mux--current-session) (user-error "No session")))
         (ps (cl-mapcan (lambda (w) (copy-sequence (ghostel-mux--window-panes w)))
                        (ghostel-mux--session-windows s))))
    (when (ghostel-mux--confirm-close ps "Close session")
      (dolist (p ps)
        (when (buffer-live-p (ghostel-mux--pane-buffer p))
          (with-current-buffer (ghostel-mux--pane-buffer p)
            (let ((ghostel-query-before-killing nil)) (kill-buffer))))))))

(defun ghostel-mux--buffer-killed ()
  (when ghostel-mux--pane
    (ghostel-mux--flush-log ghostel-mux--pane)
    (unless ghostel-mux--closing
      (let* ((p ghostel-mux--pane) (w (ghostel-mux--pane-window p))
             (s (ghostel-mux--window-session w)))
        ;; Keep manual Emacs layout changes when an asynchronous exit occurs.
        (when-let ((frame (ghostel-mux--session-frame s)))
          (when (and (frame-live-p frame)
                     (eq s (frame-parameter frame 'ghostel-mux-session)))
            (with-selected-frame frame
              (with-current-buffer (window-buffer (selected-window))
                (ghostel-mux--capture)))))
        (setf (ghostel-mux--window-panes w) (delq p (ghostel-mux--window-panes w)))
        (when (ghostel-mux--auto-tile-p w) (puthash w t ghostel-mux--dirty-layouts))
        (when (eq p (ghostel-mux--window-active w))
          (setf (ghostel-mux--window-active w) (car (ghostel-mux--window-panes w))))
        (when (eq p (ghostel-mux--window-zoom-pane w))
          (setf (ghostel-mux--window-zoom-pane w) nil
                (ghostel-mux--window-state w) (ghostel-mux--window-zoom-state w)
                (ghostel-mux--window-zoom-state w) nil))
        (unless (ghostel-mux--window-panes w)
          (setf (ghostel-mux--session-windows s) (delq w (ghostel-mux--session-windows s)))
          (when (eq w (ghostel-mux--session-current s))
            (setf (ghostel-mux--session-current s) (car (ghostel-mux--session-windows s)))))
        ;; Run after kill-buffer has replaced the dead buffer in live windows.
        (run-at-time 0 nil #'ghostel-mux--reconcile s)))))
(defun ghostel-mux--reconcile (s)
  (when (memq s ghostel-mux--sessions)
   (let* ((owner (ghostel-mux--session-frame s))
          (frame (and owner (frame-live-p owner)
                      (eq s (frame-parameter owner 'ghostel-mux-session)) owner)))
    (cond
     ((and frame (frame-parameter frame 'ghostel-mux-preview))
      (set-frame-parameter frame 'ghostel-mux-preview-reconcile t))
     ((and frame (ghostel-mux--tree-active-p frame))
      (unless (ghostel-mux--session-windows s) (ghostel-mux--finish-move (list s))))
     ((null (ghostel-mux--session-windows s))
        (progn
          (when (and frame (frame-live-p frame))
            (with-selected-frame frame (ghostel-mux-detach)))
          (setq ghostel-mux--sessions (delq s ghostel-mux--sessions))))
     (t (when (and frame (frame-live-p frame))
          (with-selected-frame frame (ghostel-mux--restore (ghostel-mux--session-current s))))))
    (ghostel-mux--refresh))))

;;; Copy behavior from the supplied tmux configuration
(defun ghostel-mux-copy-mode ()
  "Enter copy mode and show its selection controls."
  (interactive)
  (unless (eq ghostel--input-mode 'copy) (ghostel-copy-mode))
  (ghostel-mux--refresh)
  (message "COPY MODE — M-w copy/stay · C-w copy/exit · q return to terminal"))
(defun ghostel-mux-copy-selection ()
  "Copy and clear selection, staying in copy mode."
  (interactive)
  (when (use-region-p) (kill-ring-save (region-beginning) (region-end)))
  (deactivate-mark))
(defun ghostel-mux-copy-selection-and-exit ()
  "Copy and return to terminal input; never delete terminal output."
  (interactive)
  (ghostel-mux-copy-selection)
  (ghostel-semi-char-mode)
  (ghostel-mux--refresh))
(defun ghostel-mux-clear-selection () (interactive) (deactivate-mark))
(defun ghostel-mux-copy-mouse-click (event)
  "Move to EVENT and clear selection without leaving copy mode."
  (interactive "e") (mouse-set-point event) (deactivate-mark))
(defun ghostel-mux-copy-mouse-word (event)
  "Select the word at EVENT, preserving copy mode."
  (interactive "e")
  (mouse-set-point event)
  (when-let ((bounds (bounds-of-thing-at-point 'word)))
    (goto-char (car bounds)) (push-mark (cdr bounds) t t)))
(defun ghostel-mux-copy-mouse-line (event)
  "Select the whole line at EVENT, preserving copy mode."
  (interactive "e")
  (mouse-set-point event)
  (beginning-of-line)
  (push-mark (min (point-max) (1+ (line-end-position))) t t))
(defun ghostel-mux-copy-exit ()
  (interactive) (ghostel-semi-char-mode) (ghostel-mux--refresh))
(defun ghostel-mux-export-scrollback (file)
  "Export the retained, unwrapped scrollback as UTF-8 text to FILE."
  (interactive "FExport scrollback: ")
  (ghostel-mux--require-pane)
  (let ((text (ghostel--copy-all-text ghostel--term))
        (coding-system-for-write 'utf-8-unix))
    (write-region (or text "") nil file nil 'silent))
  (message "Scrollback exported to %s" file))

;;; Audit output: append raw bytes, never input/password capture
(defun ghostel-mux--safe-filename (s)
  (replace-regexp-in-string "[^[:alnum:]_.-]" "_" s))
(defun ghostel-mux--open-log (p)
  (when (file-remote-p ghostel-mux-log-directory)
    (user-error "Mux output logs must use a local directory"))
  (let* ((dir (file-name-as-directory (expand-file-name ghostel-mux-log-directory)))
         (w (ghostel-mux--pane-window p))
         (s (ghostel-mux--window-session w)))
    (unless (file-directory-p dir)
      (make-directory dir t) (set-file-modes dir #o700))
    (let ((file (make-temp-file
                 (expand-file-name
                  (format "%s-w%d-p%d-%s-" (ghostel-mux--safe-filename
                                             (ghostel-mux--session-name s))
                          (ghostel-mux--window-id w) (ghostel-mux--pane-id p)
                          (format-time-string "%Y%m%d-%H%M%S")) dir)
                 nil ".log")))
      (set-file-modes file #o600)
      (setf (ghostel-mux--pane-log-file p) file))))
(defun ghostel-mux--record-output (process output)
  (when-let* ((buf (process-buffer process))
              (p (and (buffer-live-p buf) (buffer-local-value 'ghostel-mux--pane buf))))
    (when (and (ghostel-mux--pane-log-file p) (not (ghostel-mux--pane-log-error p)))
      (push output (ghostel-mux--pane-log-chunks p))
      (cl-incf (ghostel-mux--pane-log-bytes p) (string-bytes output))
      (when (>= (ghostel-mux--pane-log-bytes p) 65536) (ghostel-mux--flush-log p)))))
(defun ghostel-mux--flush-log (p)
  (when (and (ghostel-mux--pane-log-chunks p) (not (ghostel-mux--pane-log-error p)))
    (condition-case err
        (let ((coding-system-for-write 'binary)
              (write-region-inhibit-fsync t)
              (data (apply #'concat (reverse (ghostel-mux--pane-log-chunks p)))))
          (write-region data nil (ghostel-mux--pane-log-file p) t 'silent)
          (setf (ghostel-mux--pane-log-chunks p) nil (ghostel-mux--pane-log-bytes p) 0))
      (error
       (setf (ghostel-mux--pane-log-error p) (error-message-string err))
       (display-warning 'ghostel-mux
                        (format "Recording stopped for pane %s: %s"
                                (ghostel-mux--pane-title p) (error-message-string err)))))))
(defun ghostel-mux-flush-logs ()
  (interactive) (mapc #'ghostel-mux--flush-log (ghostel-mux--all-panes)))
(defun ghostel-mux-open-log ()
  "Open this pane's raw recording in another Emacs window."
  (interactive)
  (let ((p (ghostel-mux--require-pane)))
    (unless (ghostel-mux--pane-log-file p) (user-error "Recording disabled for this pane"))
    (ghostel-mux--flush-log p)
    (find-file-read-only-other-window (ghostel-mux--pane-log-file p))))

;;; Broadcast adapter: semantic operations, not encoded byte duplication
(defun ghostel-mux--visible-panes (w &optional frame)
  "Return live W panes actually displayed in its current FRAME.
Hidden buffers, other mux windows, other sessions and other frames never
participate.  Duplicate Emacs views of a buffer count as one recipient."
  (let* ((frame (or frame (selected-frame)))
         (s (frame-parameter frame 'ghostel-mux-session)))
    (when (and (eq (frame-visible-p frame) t) s
               (eq frame (ghostel-mux--session-frame s))
               (eq w (ghostel-mux--session-current s)))
      (cl-delete-duplicates
       (cl-loop for win in (window-list frame 'no-minibuffer)
                for p = (buffer-local-value 'ghostel-mux--pane (window-buffer win))
                when (and p (eq w (ghostel-mux--pane-window p))
                          (memq p (ghostel-mux--window-panes w))
                          (ghostel-mux--pane-live-p p)) collect p)
       :test #'eq))))

(defun ghostel-mux--sync-label (w)
  "Describe W's sync state and its effective visible recipients."
  (cond
   ((frame-parameter nil 'ghostel-mux-preview) "PREVIEW · INPUT BLOCKED")
   ((not (ghostel-mux--window-sync w)) "SYNC OFF (LOCAL)")
   (t (let* ((panes (sort (ghostel-mux--visible-panes w)
                         (lambda (a b) (< (ghostel-mux--pane-number a) (ghostel-mux--pane-number b)))))
             (n (length panes)))
        (if (> n 1)
            (format "SYNC:%d [%s]" n
                    (mapconcat (lambda (p) (format "P%d" (ghostel-mux--pane-number p))) panes ","))
          (concat "SYNC PAUSED (LOCAL)"
                  (if (ghostel-mux--window-zoom-state w) " · ZOOM"
                    (format " · %d visible" n))))))))

(defun ghostel-mux-toggle-sync ()
  "Toggle broadcast in the attached mux window, even from a foreign pane."
  (interactive)
  (let ((w (ghostel-mux--require-window)))
    (setf (ghostel-mux--window-sync w) (not (ghostel-mux--window-sync w)))
    (ghostel-mux--refresh)
    (message "%s — %s%s" (ghostel-mux--group-name w) (ghostel-mux--sync-label w)
             (if (and ghostel-mux--pane
                      (not (eq w (ghostel-mux--pane-window ghostel-mux--pane))))
                 (format "; selected %s stays LOCAL (C-b a: activate its group)"
                         (ghostel-mux--group-name (ghostel-mux--pane-window ghostel-mux--pane)))
               ""))))

(defun ghostel-mux--input-command (orig &rest args)
  "Establish interactive intent only at a known terminal input command."
  (let ((ghostel-mux--input-source
         (or ghostel-mux--input-source
             (and (called-interactively-p 'any) ghostel-mux--pane (current-buffer)))))
    (apply orig args)))
(defun ghostel-mux--dispatch (orig &rest args)
  "Send once per visible live pane, using each pane's encoder."
  (when (and ghostel-mux--input-source (frame-parameter nil 'ghostel-mux-preview))
    (user-error "Finish Mux selection before sending terminal input"))
  (if (or ghostel-mux--dispatching ghostel-mux--suppress-input
          (not (eq (current-buffer) ghostel-mux--input-source))
          (null ghostel-mux--pane)
          (not (eq (current-buffer) (window-buffer (selected-window))))
          (not (eq (ghostel-mux--pane-window ghostel-mux--pane)
                   (ghostel-mux--current-window)))
          (not (ghostel-mux--window-sync (ghostel-mux--pane-window ghostel-mux--pane))))
      (apply orig args)
    (let* ((source (current-buffer))
           (w (ghostel-mux--pane-window ghostel-mux--pane))
           (frame (selected-frame))
           (targets (ghostel-mux--visible-panes w frame))
           (ghostel-mux--dispatching t) (result nil) (failures nil))
      ;; The active pane must not receive input twice through nested fallbacks.
      (dolist (p targets)
        ;; Recheck visibility if an encoder yields to a timer or changes layout.
        (when (and (eq frame (selected-frame))
                   (memq p (ghostel-mux--visible-panes w frame)))
          (with-current-buffer (ghostel-mux--pane-buffer p)
            (condition-case err
                (let ((value (apply orig args)))
                  (when (eq (current-buffer) source) (setq result value)))
              (error (push (cons (ghostel-mux--pane-id p) (error-message-string err)) failures))))))
      (when failures
        (setf (ghostel-mux--window-sync w) nil)
        (display-warning 'ghostel-mux (format "SYNC disabled after partial delivery: %S" failures)))
      result)))
(defun ghostel-mux--output-filter (orig process output)
  "Record OUTPUT, keeping terminal replies and shell callbacks local."
  (ghostel-mux--record-output process output)
  (let ((ghostel-mux--suppress-input t)) (funcall orig process output)))
(defun ghostel-mux--local-only (orig &rest args)
  (let ((ghostel-mux--suppress-input t)) (apply orig args)))

(defun ghostel-mux--dispatch-write (orig term bytes)
  "Adapt Ghostel's direct PTY writes to the semantic dispatcher."
  (if (and (eq term ghostel--term) ghostel-mux--pane
           (eq (current-buffer) ghostel-mux--input-source))
      (ghostel-mux--dispatch
       (lambda (text) (funcall orig ghostel--term text)) bytes)
    (funcall orig term bytes)))

(defun ghostel-mux-send-prefix ()
  "Send the literal configured prefix, broadcasting when enabled."
  (interactive)
  (let ((ghostel-mux--input-source (current-buffer)))
    (dolist (event (listify-key-sequence ghostel-mux-prefix-key))
      (let* ((base (event-basic-type event))
             (mods (event-modifiers event))
             (key (cond ((eq base 'backtab) "tab")
                        ((eq base 'deletechar) "delete")
                        ((characterp base) (string base))
                        ((symbolp base) (symbol-name base)))))
        (unless key (user-error "Cannot encode prefix event %S" event))
        (ghostel-send-key
         key (mapconcat #'identity
                        (delq nil (mapcar (lambda (mod)
                                           (pcase mod ('control "ctrl") ('meta "alt")
                                             ('alt "alt") ('shift "shift")
                                             ('super "super") ('hyper "hyper")))
                                         (if (eq base 'backtab) (cons 'shift mods) mods)))
                        ","))))))
(defun ghostel-mux-paste ()
  (interactive)
  (let ((ghostel-mux--input-source (current-buffer))) (ghostel-paste)))
(defun ghostel-mux-yank-pop ()
  "Replace the preceding yank in each synchronized pane."
  (interactive)
  (let ((ghostel-mux--input-source (current-buffer)))
    (call-interactively #'ghostel-yank-pop)))

;;; Presentation and prefix
(defun ghostel-mux--pane-selected-p (p)
  "Whether P is the pane currently selected for input in this frame."
  (and (not (frame-parameter nil 'ghostel-mux-preview))
       (if (eq ghostel-mux--rendering-selected 'outside)
           (eq (ghostel-mux--pane-buffer p) (window-buffer (selected-window)))
         ghostel-mux--rendering-selected)))

(defun ghostel-mux--render (part)
  "Render PART with the true selected-window flag supplied by Emacs redisplay."
  (when ghostel-mux--pane
    (let ((ghostel-mux--rendering-selected (mode-line-window-selected-p))
          ;; Redisplay temporarily selects each window whose bars it draws.
          (ghostel-mux--rendering-source-window (old-selected-window)))
      (list (funcall (if (eq part 'header) #'ghostel-mux--header #'ghostel-mux--status)
                     ghostel-mux--pane)))))

(defun ghostel-mux--set-presentation ()
  "Install Mux's theme-aware status and header forms in the current pane."
  (setq-local mode-line-format '((:eval (ghostel-mux--render 'status)))
              header-line-format '((:eval (ghostel-mux--render 'header)))))

(defun ghostel-mux--sync-target-p (p)
  "Whether P receives broadcast from the terminal selected for input now."
  (unless (frame-parameter nil 'ghostel-mux-preview)
    (let* ((win (or ghostel-mux--rendering-source-window (selected-window)))
           (buf (and (window-live-p win) (window-buffer win)))
           (source (and buf (buffer-local-value 'ghostel-mux--pane buf)))
           (w (ghostel-mux--current-window)))
      (when (and source w (eq w (ghostel-mux--pane-window source))
                 (ghostel-mux--pane-live-p source)
                 (ghostel-mux--window-sync w))
        (let ((targets (ghostel-mux--visible-panes w)))
          (and (> (length targets) 1) (memq source targets) (memq p targets)))))))

(defun ghostel-mux--pane-role (p)
  "Describe P's input role, independently of its terminal title."
  (cond ((frame-parameter nil 'ghostel-mux-preview) "PREVIEW")
        ((ghostel-mux--pane-selected-p p)
         (if (eq (ghostel-mux--pane-window p) (ghostel-mux--current-window))
             "SELECTED" "SELECTED · LOCAL"))
        ((not (eq (ghostel-mux--pane-window p) (ghostel-mux--current-window))) "OTHER GROUP")
        ((ghostel-mux--sync-target-p p)
         "SYNC TARGET")
        (t "INACTIVE")))

(defun ghostel-mux--scope-help (p)
  "Explain the distinction between P's owner and the attached group."
  (format "Owner: %s, buffer B%d. Active group: %s.\n[S] marks broadcast recipients of input from the selected terminal.\nC-b y toggles SYNC in the active group, visible live panes only.\nC-b M-5 restores that group's panes. C-b a activates this terminal's group."
          (ghostel-mux--group-name (ghostel-mux--pane-window p))
          (ghostel-mux--buffer-number p)
          (ghostel-mux--group-name (ghostel-mux--current-window))))

(defun ghostel-mux--status (p)
  (let* ((w (ghostel-mux--pane-window p)) (s (ghostel-mux--window-session w))
         (current (ghostel-mux--current-window))
         (foreign (not (eq w current)))
         (prefix (frame-parameter nil 'ghostel-mux-prefix))
         (sync (and (not foreign) (ghostel-mux--window-sync w)))
         (copy (with-current-buffer (ghostel-mux--pane-buffer p)
                 (memq ghostel--input-mode '(copy emacs))))
         (face (cond (prefix 'ghostel-mux-prefix) (copy 'ghostel-mux-copy)
                     (sync 'ghostel-mux-sync) (t 'ghostel-mux-normal))))
    (propertize
     (format " %sP%d %s | %s | %s%s | %s | %s%s%s%s "
             (if copy (propertize "[COPY MODE] " 'face 'ghostel-mux-copy) "")
             (ghostel-mux--pane-number p)
             (ghostel-mux--pane-role p)
             (if (and foreign (not (frame-parameter nil 'ghostel-mux-preview)))
                 (format "LOCAL | ACTIVE %s · C-b y → %s"
                         (ghostel-mux--group-name current) (ghostel-mux--group-name current))
               (ghostel-mux--sync-label w))
             (if prefix "PREFIX | " "")
             (format "OWNER %s · B%d" (ghostel-mux--group-name w)
                     (ghostel-mux--buffer-number p))
             (mapconcat (lambda (other)
                          (format "%d:%s%s" (ghostel-mux--window-number other)
                                  (truncate-string-to-width (ghostel-mux--window-title other) 18 nil nil t)
                                  (if (eq other w) "*" "")))
                        (ghostel-mux--session-windows s) "  ")
             (concat (if (ghostel-mux--auto-tile-p w) "AUTO TILE " "MANUAL ")
                     (if (ghostel-mux--window-zoom-state w) "ZOOM " ""))
             (if (ghostel-mux--pane-log-error p) "LOG ERROR " "")
             (if (ghostel-mux--pane-live-p p) "" "EXIT ")
             (format-time-string "%H:%M %d-%b-%y"))
     'face face 'help-echo (ghostel-mux--scope-help p))))
(defun ghostel-mux--header (p)
  (let* ((w (ghostel-mux--pane-window p))
         (s (ghostel-mux--window-session w))
         (active (ghostel-mux--pane-selected-p p))
         (broadcast (ghostel-mux--sync-target-p p))
         (marker (if broadcast "[S] " ""))
         (name-start (+ 3 (length marker)))
         (copy (with-current-buffer (ghostel-mux--pane-buffer p)
                 (memq ghostel--input-mode '(copy emacs))))
         (text
          (propertize (format " %s%s %s/B%d | P%d %s | %s%s " marker (if active "●" "○")
                        (ghostel-mux--group-name w)
                        (ghostel-mux--buffer-number p)
                        (ghostel-mux--pane-number p)
                        (ghostel-mux--pane-role p)
                        (if (or (eq w (ghostel-mux--current-window))
                                (frame-parameter nil 'ghostel-mux-preview)) ""
                          (format "ACTIVE %s | " (ghostel-mux--group-name (ghostel-mux--current-window))))
                        (truncate-string-to-width (ghostel-mux--pane-title p) 60 nil nil t))
                 'face (if active 'ghostel-mux-active 'shadow)
                 'help-echo (ghostel-mux--scope-help p))))
    ;; Apply after the surrounding face, and only to the session name.
    ;; Numbers, title, COPY and input roles retain their existing faces.
    (when ghostel-mux-session-colors
      (when-let ((face (ghostel-mux--session-color s)))
        (add-face-text-property name-start (+ name-start (length (ghostel-mux--session-name s)))
                                face nil text)))
    (when broadcast
      (add-face-text-property 1 4 'ghostel-mux-broadcast-marker nil text))
    (concat (if copy
                (propertize " [COPY MODE] q:exit · M-w:copy · C-w:copy/exit |"
                            'face 'ghostel-mux-copy)
              "")
            text)))

(defun ghostel-mux--refresh (&rest _)
  (unless (or ghostel-mux--restoring (frame-parameter nil 'ghostel-mux-preview))
    (when-let* ((p (buffer-local-value 'ghostel-mux--pane (window-buffer (selected-window))))
                (w (ghostel-mux--pane-window p)))
      (when (eq w (ghostel-mux--current-window))
        (unless (eq p (ghostel-mux--window-active w))
          (setf (ghostel-mux--window-previous w) (ghostel-mux--window-active w)
                (ghostel-mux--window-active w) p))))
    (dolist (p (ghostel-mux--all-panes))
      (when (buffer-live-p (ghostel-mux--pane-buffer p))
        (with-current-buffer (ghostel-mux--pane-buffer p)
          ;; Also upgrade the exit behavior of panes open before live reload.
          (setq-local ghostel-kill-buffer-on-exit t)
          (setq ghostel-mux--copy-active (memq ghostel--input-mode '(copy emacs)))
          (setq ghostel-mux--terminal-active (memq ghostel--input-mode '(char semi-char)))
          ;; Remove only Mux's old remap when updating live 0.1.0/0.1.1 panes.
          ;; Ghostel and the user's own face remaps remain untouched.
          (when ghostel-mux--face-cookie
            (face-remap-remove-relative ghostel-mux--face-cookie)
            (setq ghostel-mux--face-cookie nil ghostel-mux--face-state nil)))))
    (dolist (frame (frame-list))
      (dolist (win (window-list frame 'no-minibuffer))
        (let ((p (buffer-local-value 'ghostel-mux--pane (window-buffer win))))
          (set-window-parameter win 'ghostel-mux-pane-id (and p (ghostel-mux--pane-id p))))))
    ;; Rebuilding a nonselected buffer during completion resets window-point.
    ;; Defer until the minibuffer closes so cancellation returns to the same row.
    (unless (active-minibuffer-window)
      (when-let ((tree (get-buffer "*Ghostel Mux Tree*")))
        (with-current-buffer tree
          (when (derived-mode-p 'ghostel-mux-tree-mode) (ghostel-mux-tree-refresh)))))
    (force-mode-line-update t)))

(defun ghostel-mux--tick ()
  (ghostel-mux-flush-logs)
  (when (>= (- (float-time) ghostel-mux--last-clock) ghostel-mux-status-interval)
    (setq ghostel-mux--last-clock (float-time))
    (ghostel-mux--refresh)))
(defun ghostel-mux--frame-deleted (frame)
  (when-let ((s (frame-parameter frame 'ghostel-mux-session)))
    (when (eq frame (ghostel-mux--session-frame s))
      (with-selected-frame frame (ghostel-mux--capture))
      (setf (ghostel-mux--session-frame s) nil))))

(defvar ghostel-mux-command-map (make-sparse-keymap))
;; A genuine Emacs prefix command: retain the same map object on live reload
;; so user bindings, the pane mode and which-key all see the same contents.
(defalias 'ghostel-mux-prefix ghostel-mux-command-map
  "Prefix for Ghostel Mux commands; type C-b ? for the command reference.")

(defun ghostel-mux--prefix-redisplay (&rest _)
  "Update the PREFIX indicator without reading or intercepting any keys."
  (let* ((buffer (window-buffer (selected-window)))
         (keys (this-command-keys-vector))
         (prefix (vconcat ghostel-mux-prefix-key))
         (pending
          (and (buffer-local-value 'ghostel-mux-pane-mode buffer)
               (>= (length keys) (length prefix))
               (equal prefix (seq-take keys (length prefix)))
               (with-current-buffer buffer (keymapp (key-binding keys))))))
    (unless (eq pending (frame-parameter nil 'ghostel-mux-prefix))
      (set-frame-parameter nil 'ghostel-mux-prefix pending)
      (force-mode-line-update t))))
(defun ghostel-mux-command ()
  "Choose a mux command by name."
  (interactive)
  (let* ((choices '("new-session" "new-window" "select-session" "select-window" "select-pane"
                    "rename-session" "rename-window" "rename-pane" "kill-session" "kill-window"
                    "split-right" "split-below" "toggle-sync" "zoom" "layout" "layout-tiled"
                    "balance" "open-log" "attach-pane-session" "next-pane" "previous-pane"
                    "export-scrollback" "detach" "doctor" "tree" "move-pane" "move-window" "toggle-auto-tile"))
         (name (completing-read "Mux command: " choices nil t)))
    (call-interactively (intern (concat "ghostel-mux-" name)))))
(defun ghostel-mux-help ()
  (interactive)
  (with-help-window "*Ghostel Mux Help*"
    (princ "GHOSTEL MUX — prefix C-b\n\n")
    (princ "Sessions: s select   S new   $ rename   d detach\n")
    (princ "          a activate the selected terminal's owning session/window\n")
    (princ "Windows:  c new   w list   n/p next/prev   l last   1..9 select   , rename   & close\n")
    (princ "Panes:    % split right   \" split below   arrows select   o/O next/prev   ; last   q numbers   P list\n")
    (princ "          z zoom   x close   M-5 tiled   Space next layout   T rename pane\n")
    (princ "          : balance (or Emacs C-x +) balances the current arrangement\n")
    (princ "Tree:     b tree (RET visit, TAB fold, m move, a auto tile, q return)\n")
    (princ "Move:     m pane to window/session   M window to session (SYNC OFF after move)\n")
    (princ "Tiling:   A toggle automatic tiling; manual sizes last until next add/remove\n")
    (princ "Input:    y SYNC toggle   C-b literal C-b   ] paste\n")
    (princ "History:  [ copy mode   = copy entire retained scrollback   e export   L raw log\n")
    (princ "Copy:     M-w copy/stay   C-w copy/exit   C-g clear selection   q exit\n")
    (princ "Other:    : command selector   ? help   r refresh presentation\n\n")
    (princ "Ghostel:  g original C-c prefix (g C-e Emacs mode, g C-j semi-char)\n")
    (princ "C-b and C-b g are native Emacs prefixes, discoverable by which-key.\n\n")
    (princ "SYNC sends only to visible live panes in the current mux window and frame.\n")
    (princ "Zoom makes input local (SYNC PAUSED); unzoom resumes visible-pane broadcast.\n")
    (princ "When a terminal process exits, its pane closes automatically.\n")
    (princ "Mouse events, terminal responses, automatic passwords and Emacs commands are not broadcast.\n")
    (princ "C-c interrupts directly in terminal mode; C-x and M-x remain Emacs keys in semi-char mode.\n")
    (princ "Detach keeps shells alive only while the Emacs process stays alive.\n")))

(dolist (entry '(("s" . ghostel-mux-select-session) ("S" . ghostel-mux-new-session)
                 ("a" . ghostel-mux-attach-pane-session)
                 ("$" . ghostel-mux-rename-session) ("d" . ghostel-mux-detach)
                 ("c" . ghostel-mux-new-window) ("w" . ghostel-mux-select-window)
                 ("n" . ghostel-mux-next-window) ("p" . ghostel-mux-previous-window)
                 ("l" . ghostel-mux-last-window) ("," . ghostel-mux-rename-window)
                 ("&" . ghostel-mux-kill-window) ("%" . ghostel-mux-split-right)
                 ("\"" . ghostel-mux-split-below) ("o" . ghostel-mux-next-pane)
                 ("O" . ghostel-mux-previous-pane)
                 (";" . ghostel-mux-last-pane) ("q" . ghostel-mux-display-panes)
                 ("P" . ghostel-mux-select-pane)
                 ("<left>" . ghostel-mux-pane-left) ("<right>" . ghostel-mux-pane-right)
                 ("<up>" . ghostel-mux-pane-up) ("<down>" . ghostel-mux-pane-down)
                 ("z" . ghostel-mux-zoom) ("x" . ghostel-mux-kill-pane)
                 ("SPC" . ghostel-mux-next-layout) ("t" . ghostel-mux-clock)
                 ("M-5" . ghostel-mux-layout-tiled)
                 ("T" . ghostel-mux-rename-pane)
                 ("b" . ghostel-mux-tree) ("m" . ghostel-mux-move-pane)
                 ("M" . ghostel-mux-move-window) ("A" . ghostel-mux-toggle-auto-tile)
                 ("y" . ghostel-mux-toggle-sync)
                 ("]" . ghostel-mux-paste) ("[" . ghostel-mux-copy-mode)
                 ("=" . ghostel-copy-all) ("e" . ghostel-mux-export-scrollback)
                 ("L" . ghostel-mux-open-log) (":" . ghostel-mux-command)
                 ("?" . ghostel-mux-help) ("r" . ghostel-mux-refresh)))
  (define-key ghostel-mux-command-map (kbd (car entry)) (cdr entry)))
(define-key ghostel-mux-command-map ghostel-mux-prefix-key #'ghostel-mux-send-prefix)
;; Share Ghostel's real map, including user customizations, rather than
;; maintaining a second list of its commands.  Direct C-c remains an interrupt.
(define-key ghostel-mux-command-map (kbd "g")
            (lookup-key ghostel-mode-map (kbd "C-c")))
(dotimes (i 10)
  (let ((n i) (command (intern (format "ghostel-mux-window-%d" i))))
    (defalias command (lambda () (interactive) (ghostel-mux-window-by-number n))
      (format "Select mux window %d." n))
    (define-key ghostel-mux-command-map (number-to-string n) command)))
(dolist (entry '(("C-<left>" -1 t) ("C-<right>" 1 t)
                 ("C-<up>" -1 nil) ("C-<down>" 1 nil)
                 ("M-<left>" -5 t) ("M-<right>" 5 t)
                 ("M-<up>" -5 nil) ("M-<down>" 5 nil)))
  (let* ((delta (nth 1 entry)) (horizontal (nth 2 entry))
         (direction (cond (horizontal (if (> delta 0) "right" "left"))
                          (t (if (> delta 0) "down" "up"))))
         (command (intern (format "ghostel-mux-resize-%s-%d" direction (abs delta)))))
    (defalias command
      (lambda () (interactive) (window-resize nil delta horizontal)
        (ghostel-mux--capture))
      (format "Resize the current pane %s by %d units." direction (abs delta)))
    (define-key ghostel-mux-command-map (kbd (car entry)) command)))

(defvar ghostel-mux-pane-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map ghostel-mux-prefix-key #'ghostel-mux-prefix)
    (define-key map [remap ghostel-yank-pop] #'ghostel-mux-yank-pop)
    map))
(defvar ghostel-mux-copy-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "M-w") #'ghostel-mux-copy-selection)
    (define-key map (kbd "C-w") #'ghostel-mux-copy-selection-and-exit)
    (define-key map (kbd "C-g") #'ghostel-mux-clear-selection)
    (define-key map (kbd "q") #'ghostel-mux-copy-exit)
    (define-key map [mouse-1] #'ghostel-mux-copy-mouse-click)
    (define-key map [double-mouse-1] #'ghostel-mux-copy-mouse-word)
    (define-key map [triple-mouse-1] #'ghostel-mux-copy-mouse-line)
    map))
(defvar ghostel-mux-terminal-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c") #'ghostel-send-C-c)
    (define-key map (kbd "C-z") #'ghostel-send-C-z)
    (define-key map (kbd "C-d") #'ghostel-send-C-d)
    map))
(defvar ghostel-mux--emulation-maps
  `((ghostel-mux--copy-active . ,ghostel-mux-copy-map)
    (ghostel-mux-pane-mode . ,ghostel-mux-pane-mode-map)
    (ghostel-mux--terminal-active . ,ghostel-mux-terminal-map)))

(defun ghostel-mux-refresh ()
  "Refresh the mux presentation after changing faces or settings."
  (interactive) (ghostel-mux--refresh))

(define-minor-mode ghostel-mux-pane-mode
  "Local presentation and command prefix for managed Ghostel panes."
  :lighter nil :keymap ghostel-mux-pane-mode-map
  (if ghostel-mux-pane-mode
      (progn
        (setq ghostel-mux--saved-presentation (list mode-line-format header-line-format))
        (ghostel-mux--set-presentation))
    (setq mode-line-format (car ghostel-mux--saved-presentation)
          header-line-format (cadr ghostel-mux--saved-presentation)
          ghostel-mux--copy-active nil ghostel-mux--terminal-active nil)
    (when ghostel-mux--face-cookie
      (face-remap-remove-relative ghostel-mux--face-cookie)
      (setq ghostel-mux--face-cookie nil ghostel-mux--face-state nil))))

;;; Ghostel adapter (tested on 0.40 and 0.53)
(defconst ghostel-mux--input-commands
  '(ghostel--self-insert ghostel--send-event ghostel-send-next-key
    ghostel-send-C-c ghostel-send-C-z ghostel-send-C-d ghostel-send-C-backslash
    ghostel-send-C-g ghostel-yank ghostel-paste ghostel-xterm-paste
    ghostel-mouse-paste-primary-or-release ghostel-line-mode-send-or-open-link
    ghostel-line-mode-send ghostel-line-mode-interrupt ghostel-line-mode-delete-char-or-eof)
  "Interactive input entry points.  Programmatic sends remain local.")
(defconst ghostel-mux--semantic-functions
  '(ghostel--send-encoded ghostel--send-string ghostel--paste-text))

(defun ghostel-mux-doctor ()
  "Report adapter availability and the current pane's recording backend."
  (interactive)
  (with-help-window "*Ghostel Mux Doctor*"
    (princ (format "Emacs: %s\nGhostel library: %s\nMux: 0.1.9\n\n"
                   emacs-version (locate-library "ghostel")))
    (princ (format "Loaded ghostel definition: %s\nCreation API: %s\n\n"
                   (symbol-file 'ghostel 'defun)
                   (if (fboundp 'ghostel-create) "ghostel-create" "ghostel with fresh-buffer prefix")))
    (dolist (fn (append ghostel-mux--input-commands ghostel-mux--semantic-functions
                        '(ghostel ghostel--filter ghostel--copy-all-text)))
      (princ (format "%s %s\n" (if (fboundp fn) "OK     " "MISSING") fn)))
    (princ (format "\nSessions: %d\nPanes: %d\nLog directory: %s\n"
                   (length ghostel-mux--sessions) (length (ghostel-mux--all-panes))
                   ghostel-mux-log-directory))))

(defun ghostel-mux--install ()
  (unless ghostel-mux--installed
    (dolist (fn (append ghostel-mux--input-commands ghostel-mux--semantic-functions
                        '(ghostel ghostel--filter ghostel--copy-all-text)))
      (unless (fboundp fn)
        (user-error "Incompatible Ghostel: missing %s; run M-x ghostel-mux-doctor" fn)))
    (dolist (fn ghostel-mux--input-commands)
      (advice-add fn :around #'ghostel-mux--input-command))
    (dolist (fn ghostel-mux--semantic-functions)
      (advice-add fn :around #'ghostel-mux--dispatch))
    (advice-add 'ghostel--write-pty :around #'ghostel-mux--dispatch-write)
    (advice-add 'ghostel--filter :around #'ghostel-mux--output-filter)
    (dolist (fn '(ghostel--events-filter ghostel--prompt-password))
      (when (fboundp fn) (advice-add fn :around #'ghostel-mux--local-only)))
    (add-to-list 'emulation-mode-map-alists 'ghostel-mux--emulation-maps)
    (add-to-list 'window-persistent-parameters '(ghostel-mux-pane-id . t))
    (add-hook 'post-command-hook #'ghostel-mux--refresh)
    (add-hook 'pre-redisplay-functions #'ghostel-mux--prefix-redisplay)
    (add-hook 'delete-frame-functions #'ghostel-mux--frame-deleted)
    (add-hook 'kill-emacs-hook #'ghostel-mux-flush-logs)
    (setq ghostel-mux--timer (run-at-time ghostel-mux-log-flush-interval
                                        ghostel-mux-log-flush-interval #'ghostel-mux--tick)
          ghostel-mux--installed t)))

(defun ghostel-mux-unload-function ()
  "Remove integration after all mux sessions have been closed."
  (when ghostel-mux--sessions
    (user-error "Close mux sessions before unloading; detach leaves them alive"))
  (when (timerp ghostel-mux--timer) (cancel-timer ghostel-mux--timer))
  (dolist (fn ghostel-mux--input-commands)
    (advice-remove fn #'ghostel-mux--input-command))
  (dolist (fn ghostel-mux--semantic-functions)
    (advice-remove fn #'ghostel-mux--dispatch))
  (advice-remove 'ghostel--write-pty #'ghostel-mux--dispatch-write)
  (advice-remove 'ghostel--filter #'ghostel-mux--output-filter)
  (dolist (fn '(ghostel--events-filter ghostel--prompt-password))
    (when (fboundp fn) (advice-remove fn #'ghostel-mux--local-only)))
  (setq emulation-mode-map-alists (delq 'ghostel-mux--emulation-maps emulation-mode-map-alists))
  (remove-hook 'post-command-hook #'ghostel-mux--refresh)
  (remove-hook 'pre-redisplay-functions #'ghostel-mux--prefix-redisplay)
  (remove-hook 'delete-frame-functions #'ghostel-mux--frame-deleted)
  (remove-hook 'kill-emacs-hook #'ghostel-mux-flush-logs)
  nil)

;; Install the new display hook also when updating an already running Mux.
(when ghostel-mux--installed
  (ghostel-mux--migrate-session-numbers)
  (dolist (s (sort (copy-sequence ghostel-mux--sessions)
                   (lambda (a b) (< (ghostel-mux--session-id a) (ghostel-mux--session-id b)))))
    (ghostel-mux--session-color s))
  (add-hook 'pre-redisplay-functions #'ghostel-mux--prefix-redisplay)
  (dolist (p (ghostel-mux--all-panes))
    (when (buffer-live-p (ghostel-mux--pane-buffer p))
      (with-current-buffer (ghostel-mux--pane-buffer p)
        (when ghostel-mux-pane-mode (ghostel-mux--set-presentation)))))
  (dolist (frame (frame-list))
    (set-frame-parameter frame 'ghostel-mux-prefix nil)))

(provide 'ghostel-mux)
;;; ghostel-mux.el ends here
