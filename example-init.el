;;; example-init.el --- Example configuration -*- lexical-binding: t; -*-

;; Ghostel must already work: try M-x ghostel first. Tested on 0.40 and 0.53.
(add-to-list 'load-path
             (expand-file-name "lisp/ghostel-mux" user-emacs-directory))

;; Start on WSL locally; run your SSH/PSMP command inside each pane.
(setq ghostel-mux-directory (expand-file-name "~")
      ghostel-mux-scrollback-bytes (* 50 1024 1024)
      ghostel-mux-log-output t
      ghostel-mux-log-directory
      (expand-file-name "ghostel-mux-logs/" user-emacs-directory))

(autoload 'ghostel-mux "ghostel-mux" nil t)
(global-set-key (kbd "C-c m") #'ghostel-mux)

;; In managed terminals: C-b prefix, C-b y SYNC, C-b s sessions.
;; Outside them: C-b keeps its normal Emacs binding.
;; To use Ghostel's native PTY backend in new panes, disable recording:
;; (setq ghostel-mux-log-output nil)

;; Session accents are enabled by default, only on the name in each header.
;; To disable them without changing the theme:
;; (setq ghostel-mux-session-colors nil)
;; Customize the palette through M-x customize-group RET ghostel-mux RET.

;; C-b o / C-b O: next / previous pane. C-b w: active-session windows with Consult preview.
;; To disable only window previews:
;; (setq ghostel-mux-window-preview nil)

;;; example-init.el ends here
