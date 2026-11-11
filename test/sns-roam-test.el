;;; sns-roam-test.el --- ert tests for sns-roam  -*- lexical-binding: t; -*-

;; Run with `mise run test'.  A batch Emacs finds org-roam and org-ml only
;; through the packages in the owner's Emacs config.  A later slice may pin
;; them somewhere else.

(require 'ert)
(require 'cl-lib)

;; `org-roam-db-location' defaults to the owner's database.  Setting it
;; before org-roam loads means its `defcustom' keeps this value, so the
;; default is never the value at any point in the run.
(defconst sns-roam-test--db-directory
  (make-temp-file "sns-roam-test-db" t)
  "Temporary directory that holds the database every test uses.")
(defconst sns-roam-test--db-location
  ;; The file must not exist yet: org-roam creates its tables only when
  ;; it opens a database file that is absent, and treats an empty one as
  ;; an old version to upgrade.
  (expand-file-name "org-roam.db" sns-roam-test--db-directory)
  "Temporary database file every test in this run uses.")
(setq org-roam-db-location sns-roam-test--db-location)
(add-hook 'kill-emacs-hook
          (lambda ()
            (delete-directory sns-roam-test--db-directory t)))

(setq package-user-dir (expand-file-name "~/.emacs.d/elpa"))
(unless (file-directory-p package-user-dir)
  (error "sns-roam tests: no packages at %s" package-user-dir))
(package-initialize)

(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory
                                          (or load-file-name buffer-file-name))))
(require 'org-roam)
(require 'org-ml)
(require 'sns-roam-api)

(defconst sns-roam-test--api-file
  (expand-file-name "../lisp/sns-roam-api.el"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "Absolute path of the library under test, fixed when this file loads.")

(defmacro sns-roam-test--with-roam-dir (&rest body)
  "Run BODY with `org-roam-directory' set to a fresh temporary directory.
Closes the database connection, then deletes the directory and the
temporary database afterwards, so each test starts with an empty
database and no test touches the owner's slipbox or its database."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "sns-roam-test" t))
          (org-roam-directory dir))
     (unwind-protect (progn ,@body)
       (org-roam-db--close)
       (when (file-exists-p sns-roam-test--db-location)
         (delete-file sns-roam-test--db-location))
       (delete-directory dir t))))

(defun sns-roam-test--kill-file-buffer (file)
  "Kill the buffer visiting FILE, if there is one."
  (let ((buffer (get-file-buffer file)))
    (when buffer
      (kill-buffer buffer))))

(defun sns-roam-test--file-text (file)
  "Return the contents of FILE as a string."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun sns-roam-test--register (file text)
  "Write TEXT to FILE and index it in the org-roam database."
  (with-temp-file file
    (insert text))
  (org-roam-db-update-file file))

(defun sns-roam-test--all-rows ()
  "Return an alist of each database table name and all its rows."
  (mapcar (lambda (schema)
            (let ((table (car schema)))
              (cons table (org-roam-db-query [:select * :from $i1] table))))
          org-roam-db--table-schemata))

(defun sns-roam-test--org-files ()
  "Return the names of the .org files in `org-roam-directory'."
  (directory-files org-roam-directory nil "\\.org\\'"))

(defun sns-roam-test--date ()
  "Return today's date as YYYY-MM-DD."
  (format-time-string "%Y-%m-%d"))

;;; --- sns-roam-meeting-note ---

(ert-deftest sns-roam-meeting-note-carries-todays-date ()
  (sns-roam-test--with-roam-dir
    (let* ((before (sns-roam-test--date))
           (result (sns-roam-meeting-note "alan-smithee-1-1"))
           (after  (sns-roam-test--date))
           (files  (sns-roam-test--org-files))
           (file   (plist-get result :file)))
      (unwind-protect
          (progn
            (should (= 1 (length files)))
            (should (string-match-p "\\`[0-9]\\{14\\}-alan_smithee_1_1\\.org\\'"
                                    (car files)))
            ;; A run that straddles midnight may legitimately carry either date.
            (should (member (plist-get result :title)
                            (list (concat "alan-smithee-1-1 " before)
                                  (concat "alan-smithee-1-1 " after))))
            (with-temp-buffer
              (insert-file-contents file)
              (should (string-match-p
                       (format "^#\\+title: %s$"
                               (regexp-quote (plist-get result :title)))
                       (buffer-string)))
              (should (string-match-p "^:KIND: +fleeting$" (buffer-string)))))
        (let ((buffer (get-file-buffer file)))
          (when buffer
            (kill-buffer buffer)))))))

(ert-deftest sns-roam-meeting-note-rejects-a-blank-series ()
  (sns-roam-test--with-roam-dir
    (let ((err (should-error (sns-roam-meeting-note "   ") :type 'error)))
      (should (equal "sns-roam-meeting-note: empty series name" (cadr err)))
      (should (null (sns-roam-test--org-files))))))

(ert-deftest sns-roam-set-body-keeps-keywords-and-headings ()
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "note.org" org-roam-directory)))
      (with-temp-file file
        (insert ":PROPERTIES:\n:ID: set-body-test\n:KIND: fleeting\n:END:\n"
                "#+title: set body test\n#+filetags: :research:\n\n"
                "Old intro one.\n\nOld intro two.\n\n"
                "* Old section\nOld section paragraph.\n"))
      (unwind-protect
          ;; The roam database is not under test; point the lookup at the file.
          (cl-letf (((symbol-function 'sns-roam--node-file-or-error)
                     (lambda (_id) file)))
            (sns-roam-set-body "set-body-test" "New intro.")
            (let ((text (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
              (should (string-match-p "^New intro\\.$" text))
              (should (string-match-p "^#\\+filetags: :research:$" text))
              (should (string-match-p "^:KIND: +fleeting$" text))
              (should (string-match-p "^\\* Old section$" text))
              (should (string-match-p "^Old section paragraph\\.$" text))
              (should-not (string-match-p "Old intro" text))))
        (let ((buffer (get-file-buffer file)))
          (when buffer
            (kill-buffer buffer)))))))

(ert-deftest sns-roam-api-declares-its-package-requirements ()
  (let* ((file sns-roam-test--api-file)
         (info (with-temp-buffer
                 (insert-file-contents file)
                 (package-buffer-info)))
         (required (mapcar #'car (package-desc-reqs info))))
    (should (eq 'sns-roam-api (package-desc-name info)))
    (should (member 'org-roam required))
    (should (member 'org-ml required))
    (should (member 'emacs required))
    (should (alist-get :url (package-desc-extras info)))
    (should (alist-get :authors (package-desc-extras info)))))

(ert-deftest sns-roam-library-installs-no-packages-when-loaded ()
  ;; A `use-package ... :ensure t' in a library installs packages while
  ;; package-vc compiles it, and a symbol it leaves in
  ;; `package-selected-packages' crashed the first start on a new machine.
  ;; Dependencies belong in the Package-Requires header.
  (dolist (file (directory-files (file-name-directory sns-roam-test--api-file)
                                 t "\\.el\\'"))
    (with-temp-buffer
      (insert-file-contents file)
      (should-not (re-search-forward ":ensure" nil t)))))

;;; --- sns-roam-create-node registers the node (slice 9) ---

(ert-deftest sns-roam-create-node-new-note-can-be-edited-at-once ()
  ;; S9.1.  A batch on 2026-11-09 failed seven times calling
  ;; `sns-roam-set-body' straight after `sns-roam-create-node' (issue #6).
  (sns-roam-test--with-roam-dir
    (should-not (org-roam-db-query [:select id :from nodes :where (= title $s1)]
                                   "Batch claim"))
    (let* ((created (sns-roam-create-node "Batch claim" "permanent"))
           (file (plist-get created :file)))
      (unwind-protect
          (let ((result (sns-roam-set-body (plist-get created :id)
                                           "The new body.")))
            (should (equal file (plist-get result :file)))
            (let ((text (sns-roam-test--file-text file)))
              (should (string-match-p "^#\\+title: Batch claim$" text))
              (should (string-match-p "^The new body\\.$" text))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-create-node-links-show-as-backlinks-at-once ()
  ;; S9.2
  (sns-roam-test--with-roam-dir
    (sns-roam-test--register
     (expand-file-name "hub.org" org-roam-directory)
     ":PROPERTIES:\n:ID: hub-id\n:END:\n#+title: Hub\n")
    (let* ((body (sns-roam--parse-body-elements
                  "Spoke builds on [[id:hub-id][Hub]]."))
           (spoke (sns-roam-create-node "Spoke" "permanent" body))
           (edges (plist-get (sns-roam-expand "hub-id") :edges)))
      (should (cl-some (lambda (edge)
                         (and (eq :backward (plist-get edge :direction))
                              (equal (plist-get spoke :id)
                                     (plist-get edge :source-id))))
                       edges)))))

(ert-deftest sns-roam-create-node-refusal-leaves-file-and-rows-alone ()
  ;; A row for a file that was not written would make a later lookup of
  ;; the ID resolve to the wrong note.
  (sns-roam-test--with-roam-dir
    (let* ((time (date-to-time "2026-01-01 09:00:00"))
           (path (expand-file-name
                  (concat (sns-roam--filename-prefix-of time)
                          "-overwrite_target.org")
                  org-roam-directory))
           (read-bytes (lambda ()
                         (with-temp-buffer
                           (insert-file-contents-literally path)
                           (buffer-string)))))
      (sns-roam-test--register
       path ":PROPERTIES:\n:ID: existing-id\n:END:\n#+title: Existing note\n")
      (let ((bytes-before (funcall read-bytes))
            (rows-before (sns-roam-test--all-rows)))
        (let ((err (should-error (sns-roam-create-node "Overwrite target"
                                                       "permanent" nil
                                                       "new-id" nil time)
                                 :type 'error)))
          (should (equal (format "sns-roam: refusing to overwrite existing file %s"
                                 path)
                         (cadr err))))
        (should (equal bytes-before (funcall read-bytes)))
        (should (equal rows-before (sns-roam-test--all-rows)))
        (should-not (org-roam-db-query [:select id :from nodes :where (= id $s1)]
                                       "new-id"))))))

(ert-deftest sns-roam-create-node-refuses-an-id-another-file-holds ()
  ;; A retried batch can reuse a pre-minted ID with a new timestamped
  ;; filename.  org-roam only warns on the duplicate, so without this
  ;; refusal the ID would keep resolving to the earlier file.
  (sns-roam-test--with-roam-dir
    (let ((earlier (expand-file-name "earlier.org" org-roam-directory)))
      (sns-roam-test--register
       earlier ":PROPERTIES:\n:ID: reused-id\n:END:\n#+title: Earlier note\n")
      (let ((rows-before (sns-roam-test--all-rows))
            (files-before (sns-roam-test--org-files)))
        (let ((err (should-error (sns-roam-create-node "Retried claim"
                                                       "permanent" nil
                                                       "reused-id")
                                 :type 'error)))
          (should (string-match-p
                   "\\`sns-roam: id \"reused-id\" already names .*earlier\\.org"
                   (cadr err))))
        (should (equal files-before (sns-roam-test--org-files)))
        (should (equal rows-before (sns-roam-test--all-rows)))
        (should (file-equal-p earlier
                              (sns-roam--registered-file "reused-id")))))))

(ert-deftest sns-roam-create-node-fails-when-indexing-does-not-register-the-id ()
  ;; Indexing can fail with only a warning, so success must come from
  ;; the ID resolving to the new file, not from the call returning.
  (sns-roam-test--with-roam-dir
    (let ((err (cl-letf (((symbol-function 'org-roam-db-update-file)
                          #'ignore))
                 (should-error (sns-roam-create-node "Unindexed claim"
                                                     "permanent" nil
                                                     "unindexed-id")
                               :type 'error))))
      (should (string-match-p
               "\\`sns-roam: id \"unindexed-id\" resolves to nil after indexing"
               (cadr err))))))

;;; --- sns-roam-create-node separates paragraphs (slice 10) ---

(defun sns-roam-test--text-from-drawer-end (file)
  "Return the text of FILE from its first :END: line to the end.
Comparing from there shows a blank line added after the drawer, after
#+title or before a headline, as well as the spacing between paragraphs."
  (let ((text (sns-roam-test--file-text file)))
    (substring text (string-match "^:END:$" text))))

(ert-deftest sns-roam-create-node-keeps-three-paragraphs-apart ()
  ;; S10.1.  On 2026-11-09 eight notes came out with their paragraphs on
  ;; consecutive lines, which org reads as one paragraph (issue #5).
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph "One.")
                           (org-ml-build-paragraph "Two.")
                           (org-ml-build-paragraph "Three."))))
           (file (plist-get created :file))
           (text (sns-roam-test--file-text file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n\nTwo.\n\nThree.\n"
                     (sns-roam-test--text-from-drawer-end file)))
      (let ((excerpt (sns-roam-excerpt (plist-get created :id)
                                       (1+ (string-match "^Two\\.$" text)))))
        (should (equal "Two." (string-trim (plist-get excerpt :text))))))))

(ert-deftest sns-roam-create-node-keeps-paragraphs-apart-before-a-headline ()
  ;; S10.2
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph "One.")
                           (org-ml-build-paragraph "Two.")
                           (org-ml-build-headline
                            :title '("Head")
                            (org-ml-build-section
                             (org-ml-build-paragraph "Under."))))))
           (file (plist-get created :file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n\nTwo.\n* Head\nUnder.\n"
                     (sns-roam-test--text-from-drawer-end file))))))

(ert-deftest sns-roam-create-node-keeps-extra-space-a-paragraph-asks-for ()
  ;; S10.3
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph :post-blank 2 "One.")
                           (org-ml-build-paragraph "Two."))))
           (file (plist-get created :file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n\n\nTwo.\n"
                     (sns-roam-test--text-from-drawer-end file))))))

(ert-deftest sns-roam-create-node-writes-a-single-paragraph-unchanged ()
  (sns-roam-test--with-roam-dir
    (let* ((created (sns-roam-create-node
                     "Probe" "permanent"
                     (list (org-ml-build-paragraph "One."))))
           (file (plist-get created :file)))
      (should (equal ":END:\n#+title: Probe\nOne.\n"
                     (sns-roam-test--text-from-drawer-end file))))))

;;; --- sns-roam-body-elements (slice 11) ---

(defun sns-roam-test--file-state (file)
  "Return FILE's bytes and modification time, to show a call left it alone."
  (list (with-temp-buffer
          (insert-file-contents-literally file)
          (buffer-string))
        (file-attribute-modification-time (file-attributes file))))

(defun sns-roam-test--element-texts (result)
  "Return the trimmed org text of each element in RESULT's :elements."
  (mapcar #'org-ml-to-trimmed-string (plist-get result :elements)))

(ert-deftest sns-roam-body-elements-returns-the-paragraphs-before-the-first-headline ()
  ;; S11.1.  On 2026-11-09 the only way to get a note's paragraphs was to
  ;; read its file and split on blank lines (issue #7).
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "reference.org" org-roam-directory)))
      (sns-roam-test--register
       file
       (concat ":PROPERTIES:\n:ID: reference-id\n:KIND: reference\n:END:\n"
               "#+title: Nobl9 contract\n#+filetags: :vendor:\n\n"
               "Current edition is Enterprise.\n\n"
               "Annual price is fixed for the term.\n\n"
               "Notice window is 60 days.\n\n"
               "* History\n2026-10-24: three terms offered.\n"))
      (unwind-protect
          (let* ((state-before (sns-roam-test--file-state file))
                 (result (sns-roam-body-elements "reference-id")))
            (should (equal "reference-id" (plist-get result :id)))
            (should (equal file (plist-get result :file)))
            (should (equal '("Current edition is Enterprise."
                             "Annual price is fixed for the term."
                             "Notice window is 60 days.")
                           (sns-roam-test--element-texts result)))
            (should (equal state-before (sns-roam-test--file-state file))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-body-elements-shows-unsaved-edits ()
  ;; S11.2.  The edit that follows acts on the buffer, so the text shown
  ;; as the before text must come from the buffer too.
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "priced.org" org-roam-directory)))
      (let ((coding-system-for-write 'utf-8))
        (sns-roam-test--register
         file
         (concat ":PROPERTIES:\n:ID: priced-id\n:END:\n#+title: Priced\n\n"
                 "The unit price is £100.\n\nThe term is one year.\n")))
      (let ((buffer (find-file-noselect file)))
        (unwind-protect
            (progn
              (with-current-buffer buffer
                (goto-char (point-min))
                (search-forward "£100")
                (replace-match "£120" t t))
              (let* ((state-before (sns-roam-test--file-state file))
                     (result (sns-roam-body-elements "priced-id")))
                (should (equal '("The unit price is £120."
                                 "The term is one year.")
                               (sns-roam-test--element-texts result)))
                (should (equal state-before (sns-roam-test--file-state file)))
                (with-current-buffer buffer
                  (should (buffer-modified-p))
                  (should (string-match-p "£120" (buffer-string))))))
          ;; Clear the flag so killing the buffer does not ask to save it.
          (with-current-buffer buffer
            (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest sns-roam-body-elements-returns-nil-for-a-note-with-no-body ()
  ;; S11.3
  (sns-roam-test--with-roam-dir
    (let ((file (expand-file-name "bare.org" org-roam-directory)))
      (sns-roam-test--register
       file ":PROPERTIES:\n:ID: bare-id\n:END:\n#+title: Bare\n")
      (unwind-protect
          (let ((result (sns-roam-body-elements "bare-id")))
            (should (equal "bare-id" (plist-get result :id)))
            (should (equal file (plist-get result :file)))
            (should (null (plist-get result :elements))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-body-elements-reads-back-what-create-node-wrote ()
  (sns-roam-test--with-roam-dir
    (let* ((body (sns-roam--parse-body-elements
                  "A claim stated plainly.\n\n- first ground\n- second ground\n"))
           (created (sns-roam-create-node "Probe" "permanent" body))
           (file (plist-get created :file)))
      (unwind-protect
          (should (equal '("A claim stated plainly."
                           "- first ground\n- second ground")
                         (sns-roam-test--element-texts
                          (sns-roam-body-elements (plist-get created :id)))))
        (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-body-elements-rejects-an-unknown-id ()
  (sns-roam-test--with-roam-dir
    (let ((err (should-error (sns-roam-body-elements "missing-id")
                             :type 'error)))
      (should (equal "sns-roam: no roam node with id \"missing-id\""
                     (cadr err))))))

;;; --- sns-roam-insert-element (slice 12) ---

(defconst sns-roam-test--reference-header
  ":PROPERTIES:\n:ID: contract-id\n:KIND: reference\n:END:\n#+title: Vendor contract\n\n"
  "Drawer and title of the reference note the slice 12 tests edit.")

(defun sns-roam-test--containing (text)
  "Return a predicate true of an org-ml node whose text contains TEXT."
  (lambda (node)
    (string-match-p (regexp-quote text) (org-ml-to-trimmed-string node))))

(defmacro sns-roam-test--with-reference-note (body-text &rest body)
  "Run BODY with `file' bound to a registered reference note.
The note is `sns-roam-test--reference-header' followed by BODY-TEXT,
with ID \"contract-id\".  Kills the note's buffer afterwards."
  (declare (indent 1))
  `(sns-roam-test--with-roam-dir
     (let ((file (expand-file-name "contract.org" org-roam-directory)))
       (sns-roam-test--register
        file (concat sns-roam-test--reference-header ,body-text))
       (unwind-protect (progn ,@body)
         (sns-roam-test--kill-file-buffer file)))))

(ert-deftest sns-roam-insert-element-adds-a-history-line-above-the-newest ()
  ;; S12.1.  On 2026-11-10 a rewrite of one paragraph with `set-body'
  ;; dropped a line (issue #10).
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n\n2026-10-24: offered terms.\n"
    (let ((result (sns-roam-insert-element
                   "contract-id"
                   (sns-roam-test--containing "2026-10-24")
                   (org-ml-build-paragraph "2026-11-11: signed a 2-year term."))))
      (should (equal (list :id "contract-id" :file file) result))
      (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                             "Edition: Pro.\n\nOpen: renewal date.\n\n"
                             "2026-11-11: signed a 2-year term.\n\n"
                             "2026-10-24: offered terms.\n")
                     (sns-roam-test--text-from-drawer-end file))))))

(ert-deftest sns-roam-insert-element-after-the-last-paragraph-ends-the-note ()
  ;; S12.2
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n\n2026-10-24: offered terms.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "2026-10-24")
                             (org-ml-build-paragraph "See also the vendor list.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Edition: Pro.\n\nOpen: renewal date.\n\n"
                           "2026-10-24: offered terms.\n\n"
                           "See also the vendor list.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-refuses-an-anchor-that-matches-two ()
  ;; S12.3
  (sns-roam-test--with-reference-note
      "2026-10-24: offered terms.\n\n2026-10-30: asked for a discount.\n"
    (let ((state-before (sns-roam-test--file-state file))
          (err (should-error
                (sns-roam-insert-element "contract-id"
                                         (sns-roam-test--containing "2026")
                                         (org-ml-build-paragraph "New line.")
                                         t)
                :type 'error)))
      (should (equal "sns-roam: insert-element matched 2 elements, need exactly 1"
                     (cadr err)))
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-element-refuses-an-anchor-that-matches-nothing ()
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (let ((state-before (sns-roam-test--file-state file))
          (err (should-error
                (sns-roam-insert-element "contract-id"
                                         (sns-roam-test--containing "2027")
                                         (org-ml-build-paragraph "New line."))
                :type 'error)))
      (should (equal "sns-roam: insert-element matched 0 elements, need exactly 1"
                     (cadr err)))
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-element-never-shows-the-header-to-the-predicate ()
  ;; The title and the drawer both contain "contract", so a predicate
  ;; that saw them would match three elements.
  (sns-roam-test--with-reference-note
      "The contract runs two years.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "ontract")
                             (org-ml-build-paragraph "Notice is 60 days.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "The contract runs two years.\n\n"
                           "Notice is 60 days.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-before-the-first-body-element ()
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "Edition")
                             (org-ml-build-paragraph "Vendor: Acme."))
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Vendor: Acme.\n\nEdition: Pro.\n\n"
                           "Open: renewal date.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-keeps-extra-space-after-the-anchor ()
  ;; No gap shrinks: the anchor keeps its two blank lines, and the new
  ;; paragraph has one before the body element that follows it.
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\n\nOpen: renewal date.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "Edition")
                             (org-ml-build-paragraph "Units: 40.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Edition: Pro.\n\n\nUnits: 40.\n\n"
                           "Open: renewal date.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(ert-deftest sns-roam-insert-element-after-a-footnote-keeps-the-three-apart ()
  ;; Org ends a footnote definition only at two blank lines, so a
  ;; shrunk gap would pull the new paragraph into the footnote.
  (sns-roam-test--with-reference-note
      (concat "Prices follow the list.[fn:1]\n\n"
              "[fn:1] List price as of 2026.\n\n\n"
              "Prices are per seat.\n")
    (sns-roam-insert-element "contract-id"
                             (lambda (node)
                               (org-ml-is-type 'footnote-definition node))
                             (org-ml-build-paragraph "Counts are at renewal.")
                             t)
    (let ((elements (plist-get (sns-roam-body-elements "contract-id")
                               :elements)))
      (should (equal '(paragraph footnote-definition paragraph paragraph)
                     (mapcar #'org-ml-get-type elements)))
      (should (equal '("Counts are at renewal." "Prices are per seat.")
                     (mapcar #'org-ml-to-trimmed-string (cddr elements)))))))

(ert-deftest sns-roam-insert-element-refuses-a-plain-list ()
  ;; A list beside a list would merge into one, so only paragraphs go in.
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (let ((state-before (sns-roam-test--file-state file))
          (err (should-error
                (sns-roam-insert-element
                 "contract-id"
                 (sns-roam-test--containing "Edition")
                 (car (sns-roam--parse-body-elements "- seats\n- users\n"))
                 t)
                :type 'error)))
      (should (equal "sns-roam: insert-element takes a paragraph, not a plain-list"
                     (cadr err)))
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-element-refuses-a-plan-that-would-not-reparse ()
  ;; A spacing helper that leaves no blank lines makes the new paragraph
  ;; and its neighbours read back as one, which the check must catch.
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n\nOpen: renewal date.\n"
    (let ((state-before (sns-roam-test--file-state file))
          (err (cl-letf (((symbol-function 'sns-roam--insert-beside)
                          (lambda (children anchor new-element _after)
                            (cl-mapcan
                             (lambda (child)
                               (let ((flat (org-ml-set-property
                                            :post-blank 0 child)))
                                 (if (eq child anchor)
                                     (list flat (org-ml-set-property
                                                 :post-blank 0 new-element))
                                   (list flat))))
                             children))))
                 (should-error
                  (sns-roam-insert-element "contract-id"
                                           (sns-roam-test--containing "Edition")
                                           (org-ml-build-paragraph "Units: 40.")
                                           t)
                  :type 'error))))
      (should (equal (concat "sns-roam: insert-element planned 3 body elements"
                             " but they read back as 1")
                     (cadr err)))
      (should (equal state-before (sns-roam-test--file-state file))))))

(ert-deftest sns-roam-insert-into-section-is-callable-without-a-file ()
  ;; The calculation from section to section needs no database or file.
  (let* ((section (car (org-ml-get-children
                        (with-temp-buffer
                          (insert sns-roam-test--reference-header
                                  "Edition: Pro.\n\nOpen: renewal date.\n")
                          (org-ml-parse-this-buffer)))))
         (result (sns-roam--insert-into-section
                  section
                  (sns-roam-test--containing "Open")
                  (org-ml-build-paragraph "Units: 40.")
                  nil)))
    (should (equal '("Edition: Pro." "Units: 40." "Open: renewal date.")
                   (mapcar #'org-ml-to-trimmed-string
                           (seq-remove #'sns-roam--section-header-p
                                       (org-ml-get-children result)))))
    (should (equal "sns-roam: insert-element matched 2 elements, need exactly 1"
                   (cadr (should-error
                          (sns-roam--insert-into-section
                           section
                           (sns-roam-test--containing ".")
                           (org-ml-build-paragraph "Units: 40.")
                           nil)
                          :type 'error))))))

(ert-deftest sns-roam-insert-element-adds-no-blank-line-before-a-headline ()
  (sns-roam-test--with-reference-note
      "Edition: Pro.\n* History\n2026-10-24: offered terms.\n"
    (sns-roam-insert-element "contract-id"
                             (sns-roam-test--containing "Edition")
                             (org-ml-build-paragraph "Units: 40.")
                             t)
    (should (equal (concat ":END:\n#+title: Vendor contract\n\n"
                           "Edition: Pro.\n\nUnits: 40.\n"
                           "* History\n2026-10-24: offered terms.\n")
                   (sns-roam-test--text-from-drawer-end file)))))

(defconst sns-roam-test--table-between-prose
  "Seats by year:\n| 2025 | 40 |\n| 2026 | 55 |\nPrices are per seat.\n"
  "A body whose table has prose on both sides with no blank line between.")

(ert-deftest sns-roam-insert-element-after-a-table-keeps-the-prose-apart ()
  ;; Org joins a paragraph to the prose that follows it with no blank
  ;; line, so the new paragraph must not inherit the table's zero.
  (sns-roam-test--with-reference-note
      sns-roam-test--table-between-prose
    (sns-roam-insert-element "contract-id"
                             (lambda (node) (org-ml-is-type 'table node))
                             (org-ml-build-paragraph "Counts are at renewal.")
                             t)
    (should (equal '("Seats by year:"
                     "| 2025 | 40 |\n| 2026 | 55 |"
                     "Counts are at renewal."
                     "Prices are per seat.")
                   (sns-roam-test--element-texts
                    (sns-roam-body-elements "contract-id"))))))

(ert-deftest sns-roam-insert-element-before-a-table-keeps-the-prose-apart ()
  ;; The paragraph before the anchor is the new element's other neighbour.
  (sns-roam-test--with-reference-note
      sns-roam-test--table-between-prose
    (sns-roam-insert-element "contract-id"
                             (lambda (node) (org-ml-is-type 'table node))
                             (org-ml-build-paragraph "Counts are at renewal."))
    (should (equal '("Seats by year:"
                     "Counts are at renewal."
                     "| 2025 | 40 |\n| 2026 | 55 |"
                     "Prices are per seat.")
                   (sns-roam-test--element-texts
                    (sns-roam-body-elements "contract-id"))))))

(ert-deftest sns-roam-tests-use-a-temporary-database ()
  ;; The test file sets the location before it loads org-roam, so the
  ;; owner's database is never the value, setup included.
  (should (equal sns-roam-test--db-location org-roam-db-location))
  (should (string-prefix-p (file-truename temporary-file-directory)
                           (file-truename org-roam-db-location)))
  (should-not (equal (file-truename org-roam-db-location)
                     (file-truename
                      (eval (car (get 'org-roam-db-location 'standard-value)))))))

(provide 'sns-roam-test)
;;; sns-roam-test.el ends here
