;;; example-init.el --- Example configuration -*- lexical-binding: t; -*-

;; Ghostel must already work: try M-x ghostel first. Tested on 0.40 and 0.53.
;; Start on WSL locally; run your SSH/PSMP command inside each pane.
(use-package ghostel-mux
  :ensure nil
  :load-path "~/.emacs.d/lisp/ghostel-mux/"
  :commands (ghostel-mux)
  :bind ("C-c m" . ghostel-mux)
  :init
  (setq ghostel-mux-directory (expand-file-name "~")
        ghostel-mux-scrollback-bytes (* 50 1024 1024)
        ghostel-mux-log-output t))

;; If installed elsewhere, change :load-path above to the actual directory.
;; Logs default to ghostel-mux-logs/ inside user-emacs-directory.

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

;; C-b P: pane buffer preview with Consult.
;; (setq ghostel-mux-pane-preview nil) ; disable pane previews only

;; C-b b: tree; C-b m: move pane; C-b M: move window; C-b A: auto tiling.
;; Auto tiling is enabled by default. To start with manual layouts instead:
;; (setq ghostel-mux-auto-tile nil)

;;; example-init.el ends here
