;;; sns-roam-import.el --- Obsidian → org-roam import pipeline -*- lexical-binding: t; -*-
;;
;; This file is generated from roam-import.org. Do not edit directly.
;;
;;; Code:

(require 'sns-roam-api)
(require 'cl-lib)
(require 'subr-x)

(use-package yaml
  :ensure t)
(require 'yaml)

(defun sns-roam-import--read-source (path)
  "Return (:path :yaml :body) for the markdown file at PATH.

If the file has no YAML frontmatter, =:yaml= is the empty string
and =:body= is the whole file."
  (let ((raw (with-temp-buffer
               (insert-file-contents path)
               (buffer-string))))
    (if (string-match "\\`---\n\\(\\(?:.\\|\n\\)*?\\)\n---\n\\(\\(?:.\\|\n\\)*\\)\\'" raw)
        (list :path path
              :yaml (match-string 1 raw)
              :body (match-string 2 raw))
      (list :path path :yaml "" :body raw))))

(defun sns-roam-import--parse-yaml (input)
  "Parse YAML in INPUT plist's =:yaml= and add =:yaml-title=,
=:yaml-aliases=, =:yaml-date=. Any may be nil; never errors on
missing fields — title and created derivation cascades resolve
defaults downstream."
  (let* ((yaml-str (plist-get input :yaml))
         (parsed   (if (string-empty-p yaml-str)
                       nil
                     (yaml-parse-string yaml-str
                                        :object-type 'alist
                                        :sequence-type 'list)))
         (title    (alist-get 'title parsed))
         (aliases  (alist-get 'aliases parsed))
         (date     (alist-get 'date parsed)))
    (append (list :yaml-title title
                  :yaml-aliases aliases
                  :yaml-date date)
            input)))

(defun sns-roam-import--shell-pandoc-to-json (markdown)
  "Run pandoc on MARKDOWN, return the JSON AST as a string.
Errors if pandoc exits non-zero."
  (with-temp-buffer
    (let ((exit (let ((coding-system-for-write 'utf-8))
                  (call-process-region
                   markdown nil "pandoc" nil t nil
                   "-f" "markdown+wikilinks_title_after_pipe-auto_identifiers-smart"
                   "-t" "json"))))
      (unless (eq exit 0)
        (error "sns-roam-import: pandoc -t json exited %s\n%s"
               exit (buffer-string)))
      (buffer-string))))

(defun sns-roam-import--shell-pandoc-from-json-to-plain (json)
  "Run pandoc to convert JSON AST string to plain text.
Used to flatten inline emphasis / code spans / links inside an
H1 heading to plain text."
  (with-temp-buffer
    (let ((exit (let ((coding-system-for-write 'utf-8))
                  (call-process-region
                   json nil "pandoc" nil t nil
                   "-f" "json"
                   "-t" "plain"
                   "--wrap=none"))))
      (unless (eq exit 0)
        (error "sns-roam-import: pandoc -f json -t plain exited %s\n%s"
               exit (buffer-string)))
      (string-trim (buffer-string)))))

(defun sns-roam-import--first-h1-block (blocks)
  "Walk pandoc AST BLOCKS list for the first level-1 Header.
Returns the Header alist, or nil. Pure: only inspects structure."
  (cl-loop for block across blocks
           when (and (equal (alist-get 't block) "Header")
                     (let ((c (alist-get 'c block)))
                       ;; Header c is [level, attrs, inlines]
                       (and (vectorp c)
                            (= (length c) 3)
                            (= (aref c 0) 1))))
           return block))

(defun sns-roam-import--extract-first-h1 (markdown)
  "Return the plain-text content of the first H1 in MARKDOWN, or nil.
Uses pandoc's AST so all markdown grammar quirks (code fences,
blockquoted hashes, setext H1s) are handled correctly."
  (let* ((json   (sns-roam-import--shell-pandoc-to-json markdown))
         (ast    (json-parse-string json :object-type 'alist
                                    :array-type 'array))
         (blocks (alist-get 'blocks ast))
         (h1     (sns-roam-import--first-h1-block blocks)))
    (when h1
      ;; Render just this Header back to plain text. Wrap in a
      ;; minimal Pandoc envelope so pandoc -f json accepts it.
      (let* ((envelope `((pandoc-api-version . [1 23 1])
                         (meta . ,(make-hash-table :test 'equal))
                         (blocks . [,h1])))
             (envelope-json (json-serialize envelope)))
        (sns-roam-import--shell-pandoc-from-json-to-plain envelope-json)))))

(defun sns-roam-import--humanise-slug (slug)
  "Turn a filename slug into a humanised title.
=what-is-this= → =What Is This=; =atomic-notes= → =Atomic Notes=.
Splits on hyphens and underscores, title-cases each word."
  (mapconcat #'capitalize
             (split-string slug "[-_]+" t)
             " "))

(defun sns-roam-import--derive-title (input)
  "Resolve canonical =:title= via cascade; add =:title-source=.
Cascade: =:yaml-title= → first H1 of body → humanised filename slug.
Logs the source via =message= so vault hygiene issues are visible."
  (let* ((yaml-title (plist-get input :yaml-title))
         (body       (plist-get input :body))
         (path       (plist-get input :path))
         (h1         (and (not yaml-title)
                          (sns-roam-import--extract-first-h1 body)))
         (slug       (file-name-base path))
         (title      (or yaml-title
                         h1
                         (sns-roam-import--humanise-slug slug)))
         (source     (cond (yaml-title :yaml)
                           (h1         :h1)
                           (t          :filename))))
    (message "sns-roam-import: title for %s from %s → %S"
             (file-name-nondirectory path) source title)
    (append (list :title title :title-source source) input)))

(defun sns-roam-import--parse-yaml-date (date)
  "Best-effort parse of a yaml DATE field to an emacs time value.
DATE may be a string (ISO 8601 or simple =YYYY-MM-DD=) or already
a parsed value from yaml.el. Returns nil on failure rather than
erroring — the cascade has further fallbacks."
  (cond
   ((null date) nil)
   ((stringp date)
    (or (ignore-errors (parse-iso8601-time-string date))
        ;; yaml.el sometimes leaves =YYYY-MM-DD= as a bare string
        ;; that parse-iso8601-time-string rejects; pad to a full
        ;; ISO timestamp and retry.
        (and (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date)
             (ignore-errors
               (parse-iso8601-time-string (concat date "T00:00:00+00:00"))))))
   ;; yaml.el may already have decoded a date to a list — we don't
   ;; rely on that path, so fall through to nil.
   (t nil)))

(defun sns-roam-import--git-first-touch (path)
  "Return the time the file at PATH was first added to git, or nil.
Uses =magit-git-string= so process management and error handling
go through the canonical magit interface; nil on any failure
(file not in a repo, file untracked, magit not loaded)."
  (when (require 'magit nil t)
    (let* ((default-directory (file-name-directory path))
           (iso (ignore-errors
                  (magit-git-string "log" "--diff-filter=A" "--follow"
                                    "--format=%aI" "-1" "--"
                                    (file-name-nondirectory path)))))
      (when (and iso (not (string-empty-p iso)))
        (ignore-errors (parse-iso8601-time-string iso))))))

(defun sns-roam-import--derive-created (input)
  "Resolve canonical =:created-time= via cascade; add =:created-source=.
Cascade: =:yaml-date= → magit first-touch → =current-time=.
Logs the source via =message=."
  (let* ((yaml-date  (plist-get input :yaml-date))
         (path       (plist-get input :path))
         (yaml-time  (sns-roam-import--parse-yaml-date yaml-date))
         (git-time   (and (not yaml-time)
                          (sns-roam-import--git-first-touch path)))
         (time       (or yaml-time git-time (current-time)))
         (source     (cond (yaml-time :yaml)
                           (git-time  :git)
                           (t         :now))))
    (message "sns-roam-import: created for %s from %s → %s"
             (file-name-nondirectory path)
             source
             (format-time-string "[%Y-%m-%d %a %H:%M]" time))
    (append (list :created-time time :created-source source) input)))

(defun sns-roam-import--shell-pandoc (markdown)
  "Run pandoc on MARKDOWN string, return the org-formatted output.
Errors if pandoc exits non-zero."
  (with-temp-buffer
    (let ((exit (let ((coding-system-for-write 'utf-8))
                  (call-process-region
                   markdown nil "pandoc" nil t nil
                   "-f" "markdown+wikilinks_title_after_pipe-auto_identifiers-smart"
                   "-t" "org-special_strings"
                   "--shift-heading-level-by=-1"
                   "--wrap=preserve"))))
      (unless (eq exit 0)
        (error "sns-roam-import: pandoc exited %s\n%s" exit (buffer-string)))
      (buffer-string))))

(defun sns-roam-import--strip-pandoc-title (org-output)
  "Remove the leading =#+title:= line emitted by pandoc -s, if present.
We use the title from YAML directly to avoid mismatch surprises."
  (replace-regexp-in-string "\\`#\\+title:.*\n+" "" org-output))

(defun sns-roam-import--pandoc (input)
  "Run pandoc on INPUT's =:body= and add =:org-body=."
  (let* ((body     (plist-get input :body))
         (org      (sns-roam-import--shell-pandoc body))
         (cleaned  (sns-roam-import--strip-pandoc-title org)))
    (append (list :org-body cleaned)
            (cl-loop for (k v) on input by #'cddr
                     unless (eq k :body)
                     append (list k v)))))

(defun sns-roam-import--rewrite-link-ast (link uuid-map)
  "Return a rewritten LINK element if it's a file: link, else LINK unchanged.
Preserves =:post-blank= from the original so trailing whitespace
between the link and following text isn't dropped on re-emit
(otherwise =[[…]] foo= becomes =[[…]]foo=)."
  (if (string= (org-ml-get-property :type link) "file")
      (let* ((slug     (org-ml-get-property :path link))
             (children (org-ml-get-children link))
             (text     (and (stringp (car-safe children))
                            (car children)))
             (uuid     (cdr (assoc slug uuid-map)))
             (post-blank (org-ml-get-property :post-blank link))
             (rebuilt (cond
                       (uuid (org-ml-build-link (concat "id:" uuid)
                                                (or text slug)))
                       ((and text (not (string= text slug)))
                        (org-ml-build-link slug text))
                       (t (org-ml-build-link (or text slug))))))
        (org-ml-set-property :post-blank post-blank rebuilt))
    link))

(defun sns-roam-import--rewrite-wikilinks-ast (elements uuid-map)
  "Return ELEMENTS (list of org-ml AST nodes) with file: links rewritten.
Each top-level element's link descendants are rewritten via
`sns-roam-import--rewrite-link-ast'."
  (mapcar
   (lambda (element)
     (org-ml-match-map
      '(:any * link)
      (lambda (l) (sns-roam-import--rewrite-link-ast l uuid-map))
      element))
   elements))

(defun sns-roam-import--rewrite-wikilinks (uuid-map)
  "Return a stage function that rewrites wikilinks (AST stage).
Reads =:elements= from input plist, rewrites file: links via
UUID-MAP, writes the result back to =:elements=."
  (lambda (input)
    (let ((rewritten (sns-roam-import--rewrite-wikilinks-ast
                      (plist-get input :elements)
                      uuid-map)))
      (plist-put (copy-sequence input) :elements rewritten))))

(defun sns-roam-import--parse-body-elements-from-string (org-body)
  "Parse ORG-BODY (a string of org-formatted text) into a flat list
of org-ml AST nodes suitable for `sns-roam-create-node'.

The leading section's paragraph-ish children are unwrapped (so
they go into our header section); any sibling headlines pass
through untouched."
  (let* ((parsed (with-temp-buffer
                   (insert org-body)
                   (org-ml-parse-this-buffer)))
         (children (org-ml-get-children parsed)))
    (cl-mapcan (lambda (child)
                 (if (eq (org-ml-get-type child) 'section)
                     (org-ml-get-children child)
                   (list child)))
               children)))

(defun sns-roam-import--parse-body-elements (input)
  "Pipeline stage: parse INPUT plist's =:org-body= into =:elements=.
Drops =:org-body= from the output plist; downstream stages work
on the AST list under =:elements=."
  (let ((elements (sns-roam-import--parse-body-elements-from-string
                   (plist-get input :org-body))))
    (append (list :elements elements)
            (cl-loop for (k v) on input by #'cddr
                     unless (eq k :org-body)
                     append (list k v)))))

(defun sns-roam-import--create-node (input)
  "Create a roam node from INPUT, returning (:id :title :file :aliases).
Body comes from =:elements= (already AST). KIND is hard-coded
=imported= for every imported note — the importer never trusts
foreign =kind:= metadata, and =permanent= must be earned
downstream by curation against the atomic-notes heuristic. If
INPUT has a pre-assigned =:id=, it's used verbatim; otherwise
=sns-roam-create-node= generates one. Aliases pass through to the
property drawer at write time. =:created-time= (resolved by the
=derive-created= stage) is threaded into =sns-roam-create-node=
so the file's :CREATED: property and 14-digit prefix both reflect
the authored date — both formatted from the same internal time
value."
  (let* ((aliases (plist-get input :yaml-aliases))
         (created (sns-roam-create-node
                   (plist-get input :title)
                   "imported"
                   (plist-get input :elements)
                   (plist-get input :id)
                   aliases
                   (plist-get input :created-time))))
    (append created (list :aliases aliases))))

(defun sns-roam-import--inject-id (input pre-assigned-id)
  "Add =:id= PRE-ASSIGNED-ID to INPUT plist if non-nil; else return as-is.
Lets the create-node stage pick up the pre-assigned UUID
without any temporal coupling between caller and callee."
  (if pre-assigned-id
      (plist-put (copy-sequence input) :id pre-assigned-id)
    input))

(defun sns-roam-import-from-markdown (path uuid-map &optional pre-assigned-id)
  "Import the markdown file at PATH as a roam node.
UUID-MAP is the slug→UUID alist for wikilink resolution.
PRE-ASSIGNED-ID, if non-nil, is used verbatim as the new node's
UUID; otherwise a fresh one is generated. Returns the final
plist (:id :title :file :aliases)."
  (thread-last (sns-roam-import--read-source path)
               (sns-roam-import--parse-yaml)
               (sns-roam-import--derive-title)
               (sns-roam-import--derive-created)
               (sns-roam-import--pandoc)
               (sns-roam-import--parse-body-elements)
               (funcall (sns-roam-import--rewrite-wikilinks uuid-map))
               ((lambda (input) (sns-roam-import--inject-id input pre-assigned-id)))
               (sns-roam-import--create-node)))

(defun sns-roam-import--md-slug (path)
  "Return the slug for an Obsidian markdown file, derived from filename.
Obsidian wikilinks resolve by filename-without-extension, so
that's what we use as the map key."
  (file-name-base path))

(defun sns-roam-import--build-uuid-map (md-paths)
  "Return alist mapping each PATH's slug to a freshly-generated UUID.
Pure — no files touched."
  (mapcar (lambda (p)
            (cons (sns-roam-import--md-slug p) (org-id-new)))
          md-paths))

(defun sns-roam-import-vault (md-paths)
  "Import every markdown file in MD-PATHS as a roam node.
Two-pass: first derives a slug→UUID map, then threads each file
through the full pipeline carrying its pre-assigned UUID so
intra-vault wikilinks resolve correctly. Returns a list of
final plists, one per file."
  (let ((uuid-map (sns-roam-import--build-uuid-map md-paths)))
    (mapcar (lambda (p)
              (let ((pre-uuid (cdr (assoc (sns-roam-import--md-slug p)
                                          uuid-map))))
                (sns-roam-import-from-markdown p uuid-map pre-uuid)))
            md-paths)))

(provide 'sns-roam-import)
;;; sns-roam-import.el ends here
