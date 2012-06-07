(defgroup rtags nil
  "Minor mode for rtags."
  :group 'tools
  :prefix "rtags-")

(defcustom rtags-edit-hook nil
  "Run before rtags tries to modify a buffer (from rtags-rename)
return t if rtags is allowed to modify this file"
  :group 'rtags
  :type 'hook)

(defcustom rtags-jump-to-first-match t
  "If t, jump to first match"
  :group 'rtags
  :type 'boolean)

(defcustom rtags-log-enabled nil
  "If t, log"
  :group 'rtags
  :type 'boolean)

(defun rtags-find-ancestor-file(pattern)
  "Find a file named \a file in as shallow a path as possible,
  e.g. if there's a Makefile in /foobar/rtags/rc/Makefile and one
  in /foobar/rtags/Makefile it will return the latter. Wildcards
  are allowed. If multiple files match return first match. "
  (let ((best nil)
        (dir default-directory))
    (while (cond ((string= dir "") nil)
                 ((string= dir "/") nil)
                 (t t))
      (let ((match (file-expand-wildcards (concat dir pattern))))
        (if match
            (setq best (nth 0 match))))
      (setq dir (substring dir 0 (string-match "[^/]*/?$" dir))))
    best))

(defun rtags-find-ancestor-file-directory(pattern)
  (let ((match (rtags-find-ancestor-file pattern)))
    (if match
        (substring match 0 (string-match "[^/]*/?$" match)))))

(defun rtags-default-current-project ()
  (cond
   ((gtags-get-rootpath))
   ((git-root-dir))
   ((rtags-find-ancestor-file-directory "configure"))
   ((rtags-find-ancestor-file-directory "CMakeLists.txt"))
   ((rtags-find-ancestor-file-directory "*.pro"))
   ((rtags-find-ancestor-file-directory "scons.1")) ; Is this the right way to determine this?
   ((rtags-find-ancestor-file-directory "autogen.*"))
   ((rtags-find-ancestor-file-directory "Makefile*"))
   ((rtags-find-ancestor-file-directory "INSTALL*"))
   ((rtags-find-ancestor-file-directory "README*"))
   (t nil)))

;; (defvar rtags-current-project-function rtags-default-current-project)

;; (defun rtags-create-path-filter()
;;   (if (functionp rtags-current-project-function)
;;       (concat "-i" (apply 'rtags-current-project-function))
;;     nil))

(defcustom rtags-after-find-file-hook nil
  "Run after rtags has jumped to a location possibly in a new file"
  :group 'rtags
  :type 'hook)

(defvar rtags-last-buffer nil)
(defvar rtags-last-project nil)
(defvar rtags-current-path-filter nil)

(defun rtags-current-symbol ()
  (cond
   ((looking-at "[0-9A-Za-z_]")
    (while (and (not (bolp)) (looking-at "[0-9A-Za-z_]"))
      (forward-char -1))
    (if (not (looking-at "[0-9A-Za-z_]")) (forward-char 1)))
   (t
    (while (looking-at "[ \t]")
      (forward-char 1))))
  (if (looking-at "[A-Za-z_][A-Za-z_0-9]*")
      (buffer-substring (match-beginning 0) (match-end 0))
    nil))

(defun rtags-cursorinfo (&optional location)
  (let ((loc (if location location (rtags-current-location))))
    (with-temp-buffer
      (rtags-call-rc "-C" loc)
      (buffer-string))))

(defun rtags-current-location ()
  (format "%s,%d" (buffer-file-name) (- (point) 1)))

(defun rtags-print-current-location ()
  (interactive)
  (message (rtags-current-location)))

(defun rtags-log (log)
  (if rtags-log-enabled
      (save-excursion
        (set-buffer (get-buffer-create "*RTags Log*"))
        (goto-char (point-max))
        (setq buffer-read-only nil)
        (insert "**********************************\n" log "\n")
        (setq buffer-read-only t)
        )
    )
  )

(defun rtags-quit-rdm () (interactive)
  (call-process (executable-find "rc") nil nil nil "--quit-rdm"))

(defun rtags-call-rc (&rest arguments)
  (push (if rtags-log-enabled "--autostart-rdm=-L/tmp/rdm.log" "--autostart-rdm") arguments)
  (rtags-log (concat (executable-find "rc") " " (combine-and-quote-strings arguments)))
  (apply #'call-process (executable-find "rc") nil (list t nil) nil arguments)
  (rtags-log (buffer-string))
  (goto-char (point-min)))

(defvar rtags-symbol-history nil)

(defun rtags-save-location()
  (setq rtags-last-buffer (current-buffer))
  (setq rtags-last-project (rtags-default-current-project))
  (bookmark-set "RTags Last"))

(defun rtags-back()
  (interactive)
  (let ((bms (bookmark-all-names)))
    (if (member "RTags Last" bms)
        (progn
          (bookmark-rename "RTags Last" "RTags temp")
          (rtags-save-location)
          (bookmark-jump "RTags temp")
          (bookmark-delete "RTags temp")))))

(defun rtags-goto-location(location)
  "Go to a location passed in. It can be either: file,12 or file:13:14"
  (cond ((string-match "\\(.*\\):\\([0-9]+\\):\\([0-9]+\\)" location)
         (let ((line (string-to-int (match-string 2 location)))
               (column (string-to-int (match-string 3 location))))
           (find-file (match-string 1 location))
           (run-hooks rtags-after-find-file-hook)
           (goto-char (point-min))
           (forward-line (- line 1))
           (forward-char (- column 1))
           t))
        ((string-match "\\(.*\\),\\([0-9]+\\)" location)
         (let ((offset (string-to-int (match-string 2 location))))
           (find-file (match-string 1 location))
           (run-hooks rtags-after-find-file-hook)
           (goto-char (+ offset 1))
           t))
        (t nil))
  )

(defun rtags-index-project ()
  (interactive)
  (let ((makefile (read-file-name
                   "Index project Makefile: "
                   default-directory
                   nil
                   t
                   (if (file-exists-p (concat default-directory "/Makefile")) "Makefile" nil))))
    (if (file-exists-p makefile)
        (rtags-call-rc "-m" makefile))))

(defun rtags-follow-symbol-at-point()
  (interactive)
  (rtags-save-location)
  (let ((arg (rtags-current-location)))
    (with-temp-buffer
      (rtags-call-rc "-N" "-f" arg)
      (if (< (point-min) (point-max))
          (rtags-goto-location (buffer-string)))
      )
    )
  )

(defun rtags-find-references-at-point(&optional samefile)
  (interactive)
  (rtags-save-location)
  (let ((arg (rtags-current-location)))
    (if (get-buffer "*RTags Complete*")
        (kill-buffer "*RTags Complete*"))
    (switch-to-buffer (generate-new-buffer "*RTags Complete*"))
    (if samefile
        (rtags-call-rc "-l" "-z" "-r" arg)
      (rtags-call-rc "-l" "-r" arg))
    (cond ((= (point-min) (point-max)) (rtags-remove-completions-buffer))
          ((= (count-lines (point-min) (point-max)) 1) (rtags-goto-location (buffer-string)))
          (t (progn
               (goto-char (point-min))
               (compilation-mode)
               (if rtags-jump-to-first-match
                   (compile-goto-error)))))
    (not (= (point-min) (point-max)))
    )
  )

(defun rtags-find-references-at-point-samefile()
  (interactive)
  (rtags-find-references-at-point t))

(defun rtags-rename-symbol ()
  (interactive)
  (save-some-buffers) ; it all kinda falls apart when buffers are unsaved
  (let (len file pos replacewith prev (modifications 0) (filesopened 0))
    (save-excursion
      (if (looking-at "[0-9A-Za-z_~#]")
          (progn
            (while (and (> (point) 1) (looking-at "[0-9A-Za-z_~#]"))
              (backward-char))
            (if (not (looking-at "[0-9A-Za-z_~#]"))
                (forward-char))
            (setq file (buffer-file-name (current-buffer)))
            (setq pos (point))
            (while (looking-at "[0-9A-Za-z_~#]")
              (forward-char))
            (setq prev (buffer-substring pos (point)))
            (setq len (- (point) pos))
            (setq replacewith (read-from-minibuffer (format "Replace '%s' with: " prev)))
            (unless (equal replacewith "")
              (with-temp-buffer
                (rtags-call-rc "-E" "-O" "-N" "-r" (format "%s,%d" file pos))
                (while (looking-at "^\\(.*\\),\\([0-9]+\\)$")
                  (message (buffer-substring (point-at-bol) (point-at-eol)))
                  (message (format "%s %s" (match-string 1) (match-string 2)))
                  (let ((fn (match-string 1))
                        (p (string-to-number (match-string 2)))
                        (buf nil))
                    (setq buf (find-buffer-visiting fn))
                    (unless buf
                      (progn
                        (incf filesopened)
                        (setq buf (find-file-noselect fn))))
                    (if buf
                        (save-excursion
                          (set-buffer buf)
                          (if (run-hook-with-args-until-failure rtags-edit-hook)
                              (progn
                                (incf modifications)
                                (goto-char (+ p 1))
                                ;; (message (format "About to replace %s with %s at %d in %s"
                                ;;                  (buffer-substring (point) (+ (point) len))
                                ;;                  replacewith
                                ;;                  (point)
                                ;;                  fn))
                                (kill-forward-chars len)
                                (insert replacewith)
                                ))
                          )))
                  (next-line))
                )))
        (message (format "Opened %d new files and made %d modifications" filesopened modifications))))))

; (get-file-buffer FILENAME)

(defun rtags-find-symbols-by-name-internal (p switch)
  (rtags-save-location)
  (let (tagname prompt input)
    (setq tagname (rtags-current-symbol))
    (if tagname
        (setq prompt (concat p ": (default " tagname ") "))
      (setq prompt (concat p ": ")))
    (setq input (completing-read prompt (function rtags-symbolname-complete) nil nil nil rtags-symbol-history))
    (if (not (equal "" input))
        (setq tagname input))
    (if (get-buffer "*RTags Complete*")
        (kill-buffer "*RTags Complete*"))
    (switch-to-buffer (generate-new-buffer "*RTags Complete*"))
    (rtags-call-rc switch tagname "-l")
    (cond ((= (point-min) (point-max)) (rtags-remove-completions-buffer))
          ((= (count-lines (point-min) (point-max)) 1) (rtags-goto-location (buffer-string)))
          (t (progn
               (goto-char (point-min))
               (compilation-mode)
               (if rtags-jump-to-first-match
                   (compile-goto-error)))))
    (not (= (point-min) (point-max))))
    )

(defun rtags-find-symbol ()
  (interactive)
  (rtags-find-symbols-by-name-internal "Find symbol" "-F"))

(defun rtags-find-references ()
  (interactive)
  (rtags-find-symbols-by-name-internal "Find references" "-R"))

(defun rtags-remove-completions-buffer ()
  (interactive)
  (kill-buffer (current-buffer))
  (switch-to-buffer rtags-last-buffer))

(defun rtags-symbolname-completion-get (string)
  (with-temp-buffer
    (rtags-call-rc "-P" "-S" string)
    (eval (read (buffer-string)))))

(defun rtags-symbolname-completion-exactmatch (string)
  (with-temp-buffer
    (rtags-call-rc "-N" "-F" string)
    (> (point-max) (point-min))))

(defun rtags-symbolname-complete (string predicate code)
  (if (> (length string) 0)
      (cond ((eq code nil)
             (try-completion string (rtags-symbolname-completion-get string) predicate))
            ((eq code t) (rtags-symbolname-completion-get string))
            ((eq code 'lambda) (rtags-symbolname-completion-exactmatch string)))))

(provide 'rtags)
