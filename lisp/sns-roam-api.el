;;; sns-roam-api.el --- Lisp bridge into the org-roam slipbox -*- lexical-binding: t; -*-
;;
;; Author: Stephen Nelson-Smith <stephen@atalanta-systems.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1") (org-roam "20260425") (org-ml "20250514"))
;; URL: https://github.com/Atalanta/sns-roam
;; Keywords: outlines, tools
;;
;;; Commentary:
;;
;; This file is generated from roam-api.org. Do not edit directly.
;;
;;; Code:

(require 'org-roam)
(require 'cl-lib)

(define-error 'sns-roam-error "sns-roam: error")

(defvar sns-roam--error-kinds nil
  "Every condition `sns-roam-define-error' has declared, oldest first.")

(defmacro sns-roam-define-error (kind message fields)
  "Declare the failure KIND, a child of `sns-roam-error', with MESSAGE and FIELDS.
Defines the condition `sns-roam-KIND', whose message is MESSAGE after
\"sns-roam: \", and the function `sns-roam--signal-KIND', whose argument
list is FIELDS.  The function signals the condition with the plist
:kind, then each field under its keyword; a field after `&optional'
is left out when its value is nil.  KIND joins `sns-roam--error-kinds'."
  (declare (indent 2))
  (let* ((condition (intern (format "sns-roam-%s" kind)))
         (signaller (intern (format "sns-roam--signal-%s" kind)))
         (required (seq-take-while (lambda (field) (not (eq field '&optional)))
                                   fields))
         (optional (cdr (memq '&optional fields)))
         (keyword (lambda (field) (intern (format ":%s" field)))))
    `(progn
       (define-error ',condition ,(concat "sns-roam: " message) 'sns-roam-error)
       (defun ,signaller ,fields
         ,(format "Signal `%s' with the facts\n%s.\nDeclared by `sns-roam-define-error'."
                  condition (upcase (format "%s" fields)))
         (signal ',condition
                 (append (list :kind ',condition
                               ,@(mapcan (lambda (field)
                                           (list (funcall keyword field) field))
                                         required))
                         ,@(mapcar (lambda (field)
                                     `(and ,field (list ,(funcall keyword field) ,field)))
                                   optional))))
       (add-to-list 'sns-roam--error-kinds ',condition t))))

(sns-roam-define-error unknown-id "no roam node has this id"
  (id))
(sns-roam-define-error missing-file
    "the note's file is not where the database says; run M-x org-roam-db-sync"
  (id path))
(sns-roam-define-error malformed-note "the note lacks a part a roam file has"
  (missing &optional id file key name))
(sns-roam-define-error no-excerpt-container
    "no paragraph, item, quote or verse block encloses the point"
  (id point file))
(sns-roam-define-error match-count "the match is not exactly one element"
  (count &optional operation anchor))
(sns-roam-define-error unsupported-element
    "the operation does not take this element type"
  (type &optional operation title))
(sns-roam-define-error history-layout
    "the note is not in the reference-note history layout"
  (reason &optional dates))
(sns-roam-define-error bad-date "the date is not written YYYY-MM-DD"
  (date))
(sns-roam-define-error reparse-mismatch
    "the edit would not read back as planned, so nothing was written"
  (planned actual &optional file))
(sns-roam-define-error file-exists "refusing to overwrite an existing file"
  (id path &optional slug))
(sns-roam-define-error id-conflict "the id already names another file"
  (id registered path))
(sns-roam-define-error index-failure
    "after indexing, the id does not resolve to the new file"
  (id expected actual))

(defun sns-roam--add-context (data context)
  "Return condition DATA with each key of plist CONTEXT that DATA lacks.
The added keys go straight after :kind, in CONTEXT's order, so DATA
still starts with :kind and a value DATA already holds wins.  Pure."
  (let ((missing (cl-loop for (key value) on context by #'cddr
                          unless (plist-member data key)
                          append (list key value))))
    (append (seq-take data 2) missing (seq-drop data 2))))

(defun sns-roam--call-with-context (context thunk)
  "Call THUNK and return its value, adding CONTEXT to any `sns-roam-error'.
CONTEXT is a plist of what the caller knows and THUNK's calculations
do not, such as the node ID.  The condition is signalled again, with
the same symbol, as `sns-roam--add-context' extends its data.  Other
errors pass through unchanged."
  (condition-case err
      (funcall thunk)
    (sns-roam-error
     (signal (car err) (sns-roam--add-context (cdr err) context)))))

(defun sns-roam--node-to-plist (node)
  "Convert an `org-roam-node' NODE into a plist for Claude."
  (list :id       (org-roam-node-id node)
        :title    (org-roam-node-title node)
        :file     (org-roam-node-file node)
        :tags     (org-roam-node-tags node)
        :aliases  (org-roam-node-aliases node)))

(defun sns-roam-find-by-metadata (query)
  "Return roam nodes whose title, alias, or tag matches QUERY (substring, case-insensitive).

Each result is a plist of the shape
  (:id ID :title TITLE :file FILE :tags TAGS :aliases ALIASES).
QUERY is a string. Empty list on no match.

Deduped by :id — `org-roam-node-list' returns one entry per
(node, alias) pair, so a node with N aliases would otherwise
appear N+1 times."
  (let ((q (downcase query))
        (seen (make-hash-table :test 'equal))
        (results nil))
    (dolist (node (org-roam-node-list))
      (let* ((id      (org-roam-node-id node))
             (title   (or (org-roam-node-title node) ""))
             (aliases (org-roam-node-aliases node))
             (tags    (org-roam-node-tags node)))
        (when (and (not (gethash id seen))
                   (or (cl-search q (downcase title))
                       (cl-some (lambda (a) (cl-search q (downcase a))) aliases)
                       (cl-some (lambda (tg) (cl-search q (downcase tg))) tags)))
          (puthash id t seen)
          (push (sns-roam--node-to-plist node) results))))
    (nreverse results)))

(defun sns-roam--skip-header ()
  "Move point past the file's =:PROPERTIES:= drawer and =#+title:= line.
Stays at point 1 if no header found. Cheap heuristic: search
forward for =#+title:=, move to the line after; otherwise leave
point at the start of buffer."
  (goto-char (point-min))
  (when (re-search-forward "^#\\+title:.*\n" nil t)
    (goto-char (match-end 0))))

(defun sns-roam--search-file (file query)
  "Return a list of hit plists for QUERY in FILE.
Empty list if no hits or file isn't a roam node."
  (let ((re (regexp-quote query))
        (case-fold-search t)
        (hits nil))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((id (org-with-point-at 1 (org-id-get))))
        (when id
          (let* ((node (org-roam-node-from-id id))
                 (title (when node (org-roam-node-title node))))
            (sns-roam--skip-header)
            (while (re-search-forward re nil t)
              (let* ((point (match-beginning 0))
                     (line  (line-number-at-pos point))
                     (line-text
                      (string-trim
                       (buffer-substring-no-properties
                        (line-beginning-position)
                        (line-end-position)))))
                (push (list :id id
                            :title title
                            :file file
                            :line line
                            :point point
                            :hit-text line-text)
                      hits)))))))
    (nreverse hits)))

(defun sns-roam-body-search (query)
  "Return all body-text matches for QUERY across the roam slipbox.

Each result is a plist of the shape
  (:id ID :title TITLE :file FILE :line LINE :point POINT :hit-text TEXT).

Substring match, case-insensitive. The =:PROPERTIES:= drawer
and =#+title:= line are skipped so UUID/keyword noise doesn't
match. Files without an =:ID:= property drawer (i.e. not a roam
node) are skipped silently. Empty list on no match."
  (let ((files (directory-files-recursively
                org-roam-directory "\\.org\\'")))
    (cl-mapcan (lambda (f) (sns-roam--search-file f query)) files)))

(defun sns-roam--backlink-edges (target-node)
  "Return a list of backlink edge plists pointing at TARGET-NODE."
  (mapcar
   (lambda (bl)
     (let ((source (org-roam-backlink-source-node bl)))
       (list :source-id  (org-roam-node-id source)
             :target-id  (org-roam-node-id target-node)
             :direction  :backward
             :point      (org-roam-backlink-point bl)
             :context    (plist-get (org-roam-backlink-properties bl)
                                    :outline))))
   (org-roam-backlinks-get target-node)))

(defun sns-roam--forward-link-edges (source-node)
  "Return a list of forward-link edge plists from SOURCE-NODE.
Only =id:= links count; fuzzy and external links are skipped.
Loud failure if SOURCE-NODE's file has moved since the last sync."
  (let* ((file   (sns-roam--existing-file-or-error
                  (org-roam-node-id source-node)
                  (org-roam-node-file source-node)))
         (parsed (with-temp-buffer
                   (insert-file-contents file)
                   (org-mode)
                   (org-ml-parse-this-buffer)))
         (links  (org-ml-match '(:any * link) parsed)))
    (cl-loop for link in links
             when (string= (org-ml-get-property :type link) "id")
             collect
             (let* ((target-id (org-ml-get-property :path link))
                    (children (org-ml-get-children link))
                    (text-raw (and (stringp (car-safe children))
                                   (car children)))
                    (text (and text-raw (substring-no-properties text-raw))))
               (list :source-id  (org-roam-node-id source-node)
                     :target-id  target-id
                     :direction  :forward
                     :point      (org-ml-get-property :begin link)
                     :context    text)))))

(defun sns-roam-expand (id)
  "Return the one-hop subgraph around roam node ID.

Result shape:
  (:nodes (PLIST ...)
   :edges (PLIST ...))

=:nodes= contains every source/target node touched by an edge,
deduped by =:id=, plus the centre node itself. =:edges= contains
all backlinks (=:direction :backward=) and forward links
(=:direction :forward=) as edge plists.

Loud failure if ID has no roam node."
  (let* ((centre (org-roam-node-from-id id))
         (_ (unless centre
              (sns-roam--signal-unknown-id id)))
         (back-edges (sns-roam--backlink-edges centre))
         (fwd-edges  (sns-roam--forward-link-edges centre))
         (all-edges  (append back-edges fwd-edges))
         (other-ids  (delete-dups
                      (append (mapcar (lambda (e) (plist-get e :source-id)) back-edges)
                              (mapcar (lambda (e) (plist-get e :target-id)) fwd-edges))))
         (other-nodes (mapcar
                       (lambda (oid)
                         (let ((n (org-roam-node-from-id oid)))
                           (if n
                               (sns-roam--node-to-plist n)
                             ;; unresolved id — surface a stub
                             (list :id oid :title nil :file nil
                                   :tags nil :aliases nil))))
                       other-ids))
         (centre-plist (sns-roam--node-to-plist centre)))
    (list :nodes (cons centre-plist other-nodes)
          :edges all-edges)))

(defconst sns-roam--excerpt-container-types
  '(paragraph item quote-block verse-block)
  "Element types that count as excerpt containers for mining.
Walks descend past =plain-list= to its =item= children — the item
is the better excerpt unit than the whole list.")

(defun sns-roam--element-contains-point-p (element point)
  "Return non-nil if POINT lies within ELEMENT's [:begin, :end) window."
  (let ((b (org-ml-get-property :begin element))
        (e (org-ml-get-property :end element)))
    (and b e (<= b point) (< point e))))

(defun sns-roam--ancestry-at-point (root point)
  "Return the ancestry chain of elements containing POINT under ROOT.
Result is root-to-leaf, including ROOT when it contains POINT.
Each element appears once. Pure: no buffer state, no mutation."
  (when (sns-roam--element-contains-point-p root point)
    (cons root
          (cl-loop for child in (org-ml-get-children root)
                   for sub = (and (listp child)
                                  (sns-roam--ancestry-at-point child point))
                   when sub return sub))))

(defun sns-roam--headline-to-plist (h)
  "Convert headline AST node H into a plist for Claude."
  (list :level         (org-ml-get-property :level h)
        :raw-value     (org-ml-get-property :raw-value h)
        :tags          (org-ml-get-property :tags h)
        :todo-keyword  (org-ml-get-property :todo-keyword h)))

(defun sns-roam-excerpt (id point)
  "Return the excerpt container enclosing POINT in roam node ID's file.

Result shape:
  (:id ID
   :file FILE
   :point POINT
   :text TEXT
   :container-type SYMBOL
   :outline (HEADLINE-PLIST ...))

Loud failure if ID is unknown or POINT has no enclosing excerpt
container (=paragraph= / =item= / =quote-block= / =verse-block=).
The latter usually means POINT landed in a headline title line or
a property drawer — fix the upstream caller."
  (let* ((file    (sns-roam--node-file-or-error id))
         (root    (with-temp-buffer
                    (insert-file-contents file)
                    (org-mode)
                    (org-ml-parse-this-buffer)))
         (chain   (sns-roam--ancestry-at-point root point))
         (outline (cl-loop for el in chain
                           when (org-ml-is-type 'headline el)
                           collect (sns-roam--headline-to-plist el)))
         (container
          (cl-loop for el in (reverse chain)
                   when (memq (org-ml-get-type el)
                              sns-roam--excerpt-container-types)
                   return el)))
    (unless container
      (sns-roam--signal-no-excerpt-container id point file))
    (list :id              id
          :file            file
          :point           point
          :text            (string-trim (org-ml-to-string container))
          :container-type  (org-ml-get-type container)
          :outline         outline)))

(require 'org-ml)

(defun sns-roam--existing-file-or-error (id file)
  "Return FILE, the path the database holds for roam node ID, if it exists.
Signal an error otherwise.  The file goes missing when the user moves
or deletes it and has not run `org-roam-db-sync' since.  The check
runs before any buffer is visited.  So no call opens a buffer on the
missing path or saves a new file there.  A buffer the user already has
open on it keeps its unsaved edits (issue #13)."
  (unless (file-exists-p file)
    (sns-roam--signal-missing-file id file))
  file)

(defun sns-roam--node-file-or-error (id)
  "Return the file path for roam node ID, or signal an error.
Loud failure on an unknown ID, and on a file that has moved since the
last sync.  Never returns nil."
  (let ((node (org-roam-node-from-id id)))
    (unless node
      (sns-roam--signal-unknown-id id))
    (sns-roam--existing-file-or-error id (org-roam-node-file node))))

(defun sns-roam--upsert-node-property (drawer key value)
  "Return DRAWER with KEY set to VALUE.
If KEY already present, replace its value; otherwise append a new
node-property as the drawer's last child. Pure — does not mutate."
  (let* ((children (org-ml-get-children drawer))
         (found    nil)
         (updated  (mapcar
                    (lambda (np)
                      (if (and (org-ml-is-type 'node-property np)
                               (string= (org-ml-get-property :key np) key))
                          (progn
                            (setq found t)
                            (org-ml-set-property :value value np))
                        np))
                    children)))
    (org-ml-set-children
     (if found
         updated
       (append updated (list (org-ml-build-node-property key value))))
     drawer)))

(defun sns-roam--set-property-in-section (section key value)
  "Return SECTION with KEY set to VALUE in its property drawer.
Maps over the full child list and replaces only the drawer.  Raises
`sns-roam-malformed-note' when SECTION has no property drawer; the
write boundary adds the note's :id and :file.  Pure."
  (let ((drawer (cl-find-if (lambda (child)
                              (org-ml-is-type 'property-drawer child))
                            (org-ml-get-children section))))
    (unless drawer
      (sns-roam--signal-malformed-note 'property-drawer nil nil key))
    (sns-roam--map-children
     (lambda (children)
       (mapcar (lambda (child)
                 (if (eq child drawer)
                     (sns-roam--upsert-node-property drawer key value)
                   child))
               children))
     section)))

(defun sns-roam-set-property (id key value)
  "Set property KEY to VALUE in the top-level drawer of roam node ID.

ID is a roam UUID; KEY is the bare property name (no colons);
VALUE is a string. Returns (:id :file :diff), as
`sns-roam--update-section' does.  Errors if the node is
unknown, or if the file has no top-level section/drawer to
update (which would mean it isn't a well-formed roam file).
Composes through `sns-roam--update-section', so only the drawer is
written and every other element keeps its text."
  (sns-roam--update-section
   'sns-roam-set-property id
   (lambda (section)
     (sns-roam--set-property-in-section section key value))))

(defun sns-roam--section-header-p (element)
  "Non-nil if ELEMENT is roam header furniture (property-drawer or keyword)."
  (or (org-ml-is-type 'property-drawer element)
      (org-ml-is-type 'keyword element)))

(defun sns-roam--map-children (fn section)
  "Return SECTION with FN applied to its full child list.
FN takes the section's children (header furniture + body) and
returns a new child list. Pure: returns a new section, mutates
nothing.

IMPORTANT: operate on the child list as a whole. Do NOT slice it
into header/body sublists and re-`append` them. Parsed nodes carry
buffer positions and :parent backrefs; reassembling sliced sublists
of parsed nodes corrupts those, and the write in
`sns-roam--update-section' finds unchanged children by those
positions. Filtering the list in place (e.g. `seq-filter`) is safe;
slicing-and-rejoining is not.

Body helpers are expressed in terms of this:
- append: `(append children NEW)` — header stays in front untouched.
- replace-body: `(append (seq-filter #'sns-roam--section-header-p
  children) NEW-BODY)` — keep header, drop old body, add new."
  (org-ml-map-children fn section))

(defun sns-roam--parse-body-elements (string)
  "Parse STRING of org prose into a list of body elements.
A bare string parses to a single headline-less section; we return
that section's children. Empty STRING yields nil."
  (if (string-empty-p string)
      nil
    (let* ((tree    (with-temp-buffer
                      (insert string)
                      (org-ml-parse-this-buffer)))
           (section (car (org-ml-get-children tree))))
      (if section (org-ml-get-children section) nil))))

(defun sns-roam--edit-section (id file section-fn)
  "Apply pure SECTION-FN to the first section of the current buffer.
Parses the buffer as it is narrowed, so the caller widens it first.
Raises before anything is written when the note of ID in FILE has no
first section, when SECTION-FN raises, or when the edits would not
read back as planned.  Returns what `sns-roam--apply-edits' returns."
  (let ((section (car (org-ml-get-children (org-ml-parse-this-buffer)))))
    (unless (and section (org-ml-is-type 'section section))
      (sns-roam--signal-malformed-note 'section id file))
    (let* ((new-section (funcall section-fn section))
           (edits       (sns-roam--section-edits
                         (org-ml-get-children section)
                         (org-ml-get-children new-section))))
      (sns-roam--check-edits edits new-section file)
      (sns-roam--apply-edits edits))))

(defun sns-roam--update-section (operation id section-fn)
  "Apply pure SECTION-FN (section -> section) to node ID and save.
The single write boundary for every mutation of the note's first
section.  It parses the buffer, applies SECTION-FN, and writes only
the children whose text changed, as `sns-roam--section-edits'
decides.  Every child SECTION-FN left alone, and every headline after
the section, keeps the text the owner typed.  SECTION-FN raises
before anything is written, so a refusal leaves the buffer as it was.
OPERATION is the symbol of the public function that called, such as
`sns-roam-insert-element'.  An `sns-roam-error' raised while the
section is planned and checked gains :id, :file and :operation.
Loud failure on unknown ID or malformed file.  Returns (:id :file
:diff), where :diff is `sns-roam--file-diff' of the note's file as
it was on disk before the call and as the save left it, \"\" when the
file did not change.  The save also writes edits the owner had not yet
saved in the buffer, so the diff shows them too."
  (let ((file (sns-roam--node-file-or-error id)))
    (with-current-buffer (find-file-noselect file)
      ;; The file on disk, not the buffer: the save below also writes any
      ;; edits the owner has not saved, and the diff must show them.
      (let ((before (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string))))
        (sns-roam--call-with-context
         (list :id id :file file :operation operation)
         (lambda ()
           ;; The owner may have narrowed the note in Emacs.  Parse and
           ;; edit all of it.  After a refusal, `save-restriction' gives
           ;; their narrowing back.  After an edit, the narrowing comes
           ;; from `sns-roam--narrowing-after'.  A marker cannot tell an
           ;; edit that ends where the narrowing starts from one that
           ;; starts there.
           (let* ((narrowing    (when (buffer-narrowed-p)
                                  (cons (point-min) (point-max))))
                  (replacements (save-restriction
                                  (widen)
                                  (sns-roam--edit-section id file section-fn))))
             (when narrowing
               (let ((bounds (sns-roam--narrowing-after narrowing replacements)))
                 (narrow-to-region (car bounds) (cdr bounds)))))))
        (save-buffer)
        (list :id id :file file
              :diff (sns-roam--file-diff file before (sns-roam--widened-text)))))))

(defun sns-roam--widened-text ()
  "Return all of the current buffer's text, ignoring any narrowing."
  (save-restriction
    (widen)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun sns-roam-set-body (id new-body)
  "Replace the body of roam node ID with NEW-BODY.

The paragraphs and other body elements before the first heading
are replaced with NEW-BODY parsed as org prose. Property drawers,
standalone =#+= keywords (=#+title:=, =#+filetags:=) and every
existing heading with its content stay. Affiliated keywords
(=#+name:=, =#+caption:=) go with the element they precede.
NEW-BODY is a string; empty clears those body elements.
Returns (:id :file). Errors loudly on unknown ID or malformed file."
  (sns-roam--update-section
   'sns-roam-set-body id
   (lambda (section)
     (sns-roam--map-children
      (lambda (children)
        (append (seq-filter #'sns-roam--section-header-p children)
                (sns-roam--parse-body-elements new-body)))
      section))))

(defun sns-roam--kept-index (old-children start child)
  "Return the index in OLD-CHILDREN of the child CHILD leaves unchanged, or nil.
The match is at index START or later, has CHILD's :begin position,
and prints to the same `org-ml-to-string' text once CHILD's
:post-blank is set to the match's.  A child whose only change is its
blank lines is therefore kept, and `sns-roam--blank-lines-text' gives
the blank lines to write.  A built node has no :begin, so it never
matches.  Pure."
  (when-let* ((begin (org-ml-get-property :begin child)))
    (cl-position-if (lambda (old-child)
                      (and (eql begin (org-ml-get-property :begin old-child))
                           (string= (org-ml-to-string old-child)
                                    (org-ml-to-string
                                     (org-ml-set-property
                                      :post-blank
                                      (org-ml-get-property :post-blank old-child)
                                      child)))))
                    old-children
                    :start start)))

(defun sns-roam--blank-lines-text (old-child child)
  "Return the blank lines `org-ml-to-string' prints after CHILD, or nil.
Nil means CHILD has as many blank lines as OLD-CHILD, the parsed
child it keeps, so none are written.  Otherwise the text is what
`org-ml-to-string' prints for CHILD past what it prints for CHILD
with no blank lines.  Pure."
  (unless (eql (org-ml-get-property :post-blank old-child)
               (org-ml-get-property :post-blank child))
    (let ((printed (org-ml-to-string child))
          (content (org-ml-to-string (org-ml-set-property :post-blank 0 child))))
      ;; When org prints the element as other text once it has blank
      ;; lines, the element cannot keep its typed text.
      (unless (string-prefix-p content printed)
        (sns-roam--signal-unsupported-element (org-ml-get-type child)))
      (substring printed (length content)))))

(defun sns-roam--run-edit (old-children from to new-nodes blank-lines)
  "Return the edit that replaces OLD-CHILDREN from index FROM up to TO with NEW-NODES.
The edit is (:begin B :end E :text TEXT), where TEXT is the
`org-ml-to-string' text of NEW-NODES.  B is where the child at FROM
begins, or where the last child ends when FROM is past the end.  E is
where the child before TO ends, or B when the run removes no child.
A section's children follow each other with no text between them, so
these bounds cover exactly the removed children.
BLANK-LINES, when non-nil, are the new blank lines of the kept child
before FROM, which ends at B.  The edit then starts where that
child's blank lines start, a buffer fact, so it carries
:blank-lines-end B in place of :begin, and TEXT starts with
BLANK-LINES.  One edit covers both, so the blank lines and the run
are written in order at the same place.
Returns nil when the edit would remove and add nothing.  Pure."
  (when (or blank-lines (< from to) new-nodes)
    (let* ((begin (if (< from (length old-children))
                      (org-ml-get-property :begin (nth from old-children))
                    (org-ml-get-property :end (car (last old-children)))))
           (end   (if (< from to)
                      (org-ml-get-property :end (nth (1- to) old-children))
                    begin))
           (text  (mapconcat #'org-ml-to-string new-nodes "")))
      (if blank-lines
          (list :blank-lines-end begin :end end :text (concat blank-lines text))
        (list :begin begin :end end :text text)))))

(defun sns-roam--section-edits (old-children new-children)
  "Return the edits that turn the text of OLD-CHILDREN into NEW-CHILDREN.
OLD-CHILDREN are a section's parsed children; NEW-CHILDREN are the
children a transform returned for it.  Each new child that
`sns-roam--kept-index' finds unchanged keeps its typed text, apart
from blank lines it gains or loses.  Each run of other children
between two kept ones becomes one edit from `sns-roam--run-edit',
which also writes the new blank lines of the kept child before it.
The edits come last in the buffer first, so making them in order
leaves the positions of the rest as the parse gave them.  Pure."
  (let ((from 0)
        (pending-new-nodes nil)
        (blank-lines nil)
        (edits nil))
    (dolist (child new-children)
      (if-let* ((kept (sns-roam--kept-index old-children from child)))
          (progn
            (push (sns-roam--run-edit old-children from kept
                                      (reverse pending-new-nodes)
                                      blank-lines)
                  edits)
            (setq blank-lines (sns-roam--blank-lines-text
                               (nth kept old-children) child)
                  from (1+ kept)
                  pending-new-nodes nil))
        (push child pending-new-nodes)))
    (push (sns-roam--run-edit old-children from (length old-children)
                              (reverse pending-new-nodes)
                              blank-lines)
          edits)
    (delq nil edits)))

(defun sns-roam--blank-lines-begin (end)
  "Return where the blank lines that end at END begin in the current buffer.
That is the start of the line after the last one before END with a
non-blank character, or END when that line has no newline.  Trailing
spaces on that line stay where they are."
  (save-excursion
    (goto-char end)
    (skip-chars-backward " \t\n")
    (forward-line 1)
    (min end (point))))

(defun sns-roam--edit-begin (edit)
  "Return where EDIT starts in the current buffer.
That is its :begin, or for an edit with :blank-lines-end, where those
blank lines begin."
  (if-let* ((blank-lines-end (plist-get edit :blank-lines-end)))
      (sns-roam--blank-lines-begin blank-lines-end)
    (plist-get edit :begin)))

(defun sns-roam--apply-edits (edits)
  "Make EDITS from `sns-roam--section-edits' in the current buffer, in order.
Each edit replaces the text between `sns-roam--edit-begin' and its
:end with its :text.  EDITS come last in the buffer first, so each
one leaves the positions of those still to come as the parse gave
them.
A file need not end with a newline, so an edit that writes after a
last line without one starts a new line first; otherwise the new
text would join that line and change what it parses as.
Returns one (:begin B :end E :new-end N) per edit, in the order made:
the text from B to E became the text from B to N."
  (save-excursion
    (mapcar (lambda (edit)
              (let ((begin (sns-roam--edit-begin edit))
                    (end   (plist-get edit :end))
                    (text  (plist-get edit :text)))
                (delete-region begin end)
                (goto-char begin)
                (when (and (not (string-empty-p text))
                           (> begin (point-min))
                           (not (eq (char-before begin) ?\n)))
                  (insert "\n"))
                (insert text)
                (list :begin begin :end end :new-end (point))))
            edits)))

(defun sns-roam--narrowing-start-after (start replacement)
  "Return where a narrowing that began at START begins after REPLACEMENT.
A REPLACEMENT from `sns-roam--apply-edits' that ends at or before
START lies outside the narrowing, so START shifts by the change in
length.  One that starts at START or covers it is inside the
narrowing, which then begins where the new text does.  Pure."
  (let ((begin (plist-get replacement :begin))
        (end   (plist-get replacement :end)))
    (cond ((>= start end) (+ start (- (plist-get replacement :new-end) end)))
          ((> start begin) begin)
          (t start))))

(defun sns-roam--narrowing-end-after (narrowing-end replacement)
  "Return where a narrowing that ended at NARROWING-END ends after REPLACEMENT.
A REPLACEMENT from `sns-roam--apply-edits' that starts at or after
NARROWING-END lies outside the narrowing and leaves it.  One that
ends at or before NARROWING-END shifts it by the change in length.
One that covers it is inside the narrowing, which then ends where
the new text does.  Pure."
  (let ((begin   (plist-get replacement :begin))
        (end     (plist-get replacement :end))
        (new-end (plist-get replacement :new-end)))
    (cond ((<= narrowing-end begin) narrowing-end)
          ((>= narrowing-end end) (+ narrowing-end (- new-end end)))
          (t new-end))))

(defun sns-roam--narrowing-after (narrowing replacements)
  "Return NARROWING, a (START . END) cons, after REPLACEMENTS were made.
REPLACEMENTS are what `sns-roam--apply-edits' returned, in the order
it made them.  The narrowing covers the same text afterwards, grown
or shrunk only by what a replacement changed inside it.  Pure."
  (seq-reduce (lambda (bounds replacement)
                (cons (sns-roam--narrowing-start-after (car bounds) replacement)
                      (sns-roam--narrowing-end-after (cdr bounds) replacement)))
              replacements
              narrowing))

(defun sns-roam--child-signature (children)
  "Return the type and trimmed printed text of each of CHILDREN.  Pure."
  (mapcar (lambda (child)
            (list (org-ml-get-type child)
                  (org-ml-to-trimmed-string child)))
          children))

(defun sns-roam--check-edits (edits new-section file)
  "Raise unless making EDITS gives the current buffer NEW-SECTION's children.
Copies the buffer into a temporary one, makes EDITS there, and parses
the result.  The first section's children must match NEW-SECTION's
by type and trimmed text, or `sns-roam-reparse-mismatch' names FILE
and both lists, and the note's buffer is left as it was.  This catches any edit whose text
would read back as something else, such as two elements merged by a
missing line break."
  (let* ((text     (save-restriction
                     (widen)
                     (buffer-substring-no-properties (point-min) (point-max))))
         (reparsed (with-temp-buffer
                     (insert text)
                     (sns-roam--apply-edits edits)
                     (delay-mode-hooks (org-mode))
                     (let ((first (car (org-ml-get-children
                                        (org-ml-parse-this-buffer)))))
                       (when (org-ml-is-type 'section first)
                         (org-ml-get-children first))))))
    (let ((planned (sns-roam--child-signature (org-ml-get-children new-section)))
          (actual  (sns-roam--child-signature reparsed)))
      (unless (equal planned actual)
        (sns-roam--signal-reparse-mismatch planned actual file)))))

(sns-roam-define-error diff-failure "diff could not compare the note's text"
  (status output &optional file))

(defun sns-roam--diff-result (status output file)
  "Return the diff that `diff -u' printed as OUTPUT and exited with STATUS.
Status 0 means the texts are the same, so the diff is \"\".  Status 1
means they differ, so the diff is OUTPUT.  Any other status, or a
signal description string from `call-process', raises
`sns-roam-diff-failure' naming FILE.  Pure."
  (pcase status
    (0 "")
    (1 output)
    (_ (sns-roam--signal-diff-failure status output file))))

(defun sns-roam--file-diff (file before after)
  "Return a unified diff of BEFORE and AFTER, two texts of FILE.
Writes each text to a temporary file and runs the system `diff -u' on
them, labelled with FILE so the headers name the note.  Deletes the
temporary files afterwards.  See `sns-roam--diff-result' for what the
exit status gives."
  (let* ((coding-system-for-write 'utf-8-unix)
         (coding-system-for-read  'utf-8-unix)
         (before-file (make-temp-file "sns-roam-before-" nil ".org" before)))
    (unwind-protect
        (let ((after-file (make-temp-file "sns-roam-after-" nil ".org" after)))
          (unwind-protect
              (with-temp-buffer
                (let ((status (call-process "diff" nil t nil "-u"
                                            "--label" file "--label" file
                                            before-file after-file)))
                  (sns-roam--diff-result status (buffer-string) file)))
            (delete-file after-file)))
      (delete-file before-file))))

(defun sns-roam-append-link (from-id to-id label before after)
  "Append a relationship paragraph to FROM-ID linking to TO-ID.
The paragraph reads BEFORE then an inline [[id:TO-ID][LABEL]] link
then AFTER, and becomes the last body element, spaced as
`sns-roam--insert-beside' spaces an element placed after the last
child. Existing content is untouched. One-directional; org-roam
backlinks give the reverse.
The primitive does NOT dedupe — call it once per intended link.
Loud failure if FROM-ID or TO-ID is unknown. Returns (:from :to :file
:diff), :diff as `sns-roam--update-section' gives it."
  (sns-roam--node-file-or-error to-id)  ; validate target exists, loud
  (let* ((link  (org-ml-build-link (concat "id:" to-id) label))
         ;; Drop empty BEFORE/AFTER so no empty secondary-strings sneak in.
         (parts (seq-remove (lambda (x) (and (stringp x) (string-empty-p x)))
                            (list before link after)))
         (res (sns-roam--update-section
              'sns-roam-append-link from-id
              (lambda (section)
                (sns-roam--map-children
                 (lambda (children)
                   (sns-roam--insert-beside children
                                            (car (last children))
                                            (apply #'org-ml-build-paragraph parts)
                                            t))
                 section)))))
    (list :from from-id :to to-id
          :file (plist-get res :file)
          :diff (plist-get res :diff))))

(defun sns-roam-body-elements (id)
  "Return the body elements before the first heading of roam node ID.

Returns:
  (:id ID :file FILE :elements NODES)

NODES are the parsed org-ml children of the note's first section,
without the property drawer and `#+' keywords, in buffer order; nil
when there is no such body.  The note is parsed from the buffer
`find-file-noselect' returns, the one `sns-roam--update-section'
edits, so unsaved edits are included.  Writes nothing.  Errors
loudly on an unknown ID."
  (let ((file (sns-roam--node-file-or-error id)))
    (with-current-buffer (find-file-noselect file)
      ;; Read all of the note, even when the owner has narrowed it.
      (let ((first-child (car (org-ml-get-children
                               (save-restriction
                                 (widen)
                                 (org-ml-parse-this-buffer))))))
        (list :id       id
              :file     file
              :elements (when (org-ml-is-type 'section first-child)
                          (seq-remove #'sns-roam--section-header-p
                                      (org-ml-get-children first-child))))))))

(defun sns-roam-replace-element (id pred new-element)
  "Replace the unique body element of node ID matching PRED with NEW-ELEMENT.
PRED is a unary predicate on an org-ml node; NEW-ELEMENT is a built
org-ml node. Asserts exactly one match — loud error on zero or many,
so an ambiguous edit never silently hits the wrong element. Composes
through `sns-roam--update-section'. Returns (:id :file)."
  (sns-roam--update-section
   'sns-roam-replace-element id
   (lambda (section)
     (let ((matches (org-ml-match `((:pred ,pred)) section)))
       (unless (= 1 (length matches))
         (sns-roam--signal-match-count (length matches)))
       (org-ml-match-map `((:pred ,pred))
                         (lambda (_old) new-element)
                         section)))))

(defun sns-roam--insert-beside (children anchor new-element after)
  "Return CHILDREN with NEW-ELEMENT next to ANCHOR, a member of CHILDREN.
AFTER non-nil places it after ANCHOR, nil before.  The child in
front of NEW-ELEMENT keeps its post-blank, raised to at least 1,
unless it is header furniture, which is left as it was.  NEW-ELEMENT
gets post-blank 1 when a child follows it, and otherwise the
post-blank ANCHOR had.  Every other child is returned as it was.
Pure."
  (let ((at-least-one (lambda (node)
                        (org-ml-set-property
                         :post-blank
                         (max 1 (org-ml-get-property :post-blank node))
                         node))))
    (cl-mapcan
     (lambda (child next)
       (cond
        ((and (eq child anchor) after)
         (list (funcall at-least-one child)
               (org-ml-set-property
                :post-blank
                (if next 1 (org-ml-get-property :post-blank anchor))
                new-element)))
        ((eq child anchor)
         (list (org-ml-set-property :post-blank 1 new-element) child))
        ((and (eq next anchor) (not after)
              (not (sns-roam--section-header-p child)))
         (list (funcall at-least-one child)))
        (t (list child))))
     children
     (append (cdr children) (list nil)))))

(defun sns-roam--body-signature (children)
  "Return the type and trimmed text of each body element in CHILDREN."
  (mapcar (lambda (element)
            (list (org-ml-get-type element)
                  (org-ml-to-trimmed-string element)))
          (seq-remove #'sns-roam--section-header-p children)))

(defun sns-roam--check-reparse (section)
  "Return SECTION if its printed text parses back to the same body.
Compares the body elements of SECTION with those org reads from
`org-ml-to-string' of SECTION, by type and trimmed text.  Raises
`sns-roam-reparse-mismatch' on a mismatch, such as two elements merged
by too few blank lines; the write boundary adds the :file.  Pure."
  (let ((planned  (sns-roam--body-signature (org-ml-get-children section)))
        (reparsed (sns-roam--body-signature
                   (sns-roam--parse-body-elements (org-ml-to-string section)))))
    (unless (equal planned reparsed)
      (sns-roam--signal-reparse-mismatch planned reparsed))
    section))

(defun sns-roam--insert-into-section (section pred new-element after)
  "Return SECTION with paragraph NEW-ELEMENT beside the body element matching PRED.
PRED sees only body elements, never the property drawer or `#+'
keywords, and must match exactly one.  AFTER non-nil places
NEW-ELEMENT after the match, nil before.  Raises an `sns-roam:' error
when NEW-ELEMENT is not a paragraph, when PRED matches zero or many
elements, or when the result would not read back as planned.  Pure."
  (unless (org-ml-is-type 'paragraph new-element)
    (sns-roam--signal-unsupported-element (org-ml-get-type new-element)
                                          'sns-roam-insert-element))
  (let ((matches (seq-filter
                  (lambda (child)
                    (and (not (sns-roam--section-header-p child))
                         (funcall pred child)))
                  (org-ml-get-children section))))
    (unless (= 1 (length matches))
      (sns-roam--signal-match-count (length matches) 'sns-roam-insert-element))
    (sns-roam--check-reparse
     (sns-roam--map-children
      (lambda (children)
        (sns-roam--insert-beside children (car matches) new-element after))
      section))))

(defun sns-roam-insert-element (id pred new-element &optional after)
  "Insert paragraph NEW-ELEMENT beside the body element of node ID matching PRED.
PRED is a unary predicate on an org-ml node and sees only body
elements, never the property drawer or `#+' keywords.  NEW-ELEMENT
is a paragraph built with `org-ml-build-paragraph'.  AFTER non-nil
inserts after the match, nil before it.  No blank-line gap shrinks,
and every other element keeps its text.  Errors loudly, leaving the
file unchanged, when NEW-ELEMENT is not a paragraph, PRED matches
zero or many elements, the result would not read back as planned,
or ID is unknown.  Composes through `sns-roam--update-section'.
Returns (:id :file)."
  (sns-roam--update-section
   'sns-roam-insert-element id
   (lambda (section)
     (sns-roam--insert-into-section section pred new-element after))))

(defconst sns-roam--history-date-regexp
  "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\):"
  "Match the date that opens a history line, such as \"2026-11-09:\".")

(defun sns-roam--history-line-date (text)
  "Return the YYYY-MM-DD date that opens TEXT, or nil if TEXT is undated."
  (when (string-match sns-roam--history-date-regexp text)
    (match-string 1 text)))

(defun sns-roam--history-body (top-level-children)
  "Return the body paragraphs of a note whose parsed children are TOP-LEVEL-CHILDREN.
Raises an `sns-roam:' error on a heading anywhere in the note, on a
body element that is not a paragraph, or on an empty body.  Pure."
  (let ((headline (seq-find (lambda (child) (org-ml-is-type 'headline child))
                            top-level-children)))
    (when headline
      (sns-roam--signal-unsupported-element
       'headline 'sns-roam-history-anchor
       (org-ml-get-property :raw-value headline))))
  ;; With no headline, the top level is the one section, or nothing in
  ;; an empty file.
  (let ((body (seq-remove #'sns-roam--section-header-p
                          (seq-mapcat #'org-ml-get-children top-level-children))))
    (unless body
      (sns-roam--signal-history-layout 'no-paragraphs))
    (dolist (element body)
      (unless (org-ml-is-type 'paragraph element)
        (sns-roam--signal-unsupported-element (org-ml-get-type element)
                                              'sns-roam-history-anchor)))
    body))

(defun sns-roam--check-history-run (dates)
  "Raise an `sns-roam:' error unless DATES end in one run of dates, newest first.
DATES holds each body paragraph's opening date, or nil for an
undated paragraph, in buffer order.  Pure."
  (let ((run (seq-drop-while #'null dates)))
    (when (memq nil run)
      (sns-roam--signal-history-layout 'not-one-run))
    (cl-mapc (lambda (newer older)
               (when (string< newer older)
                 (sns-roam--signal-history-layout 'not-newest-first
                                                  (list newer older))))
             run (cdr run))))

(defun sns-roam--history-anchor-in (top-level-children date)
  "Return (:anchor TEXT :after BOOL) for a line dated DATE in a parsed note.
TOP-LEVEL-CHILDREN are the children of the note's parsed org-data.
TEXT is the trimmed text of the first history line dated on or
before DATE, with :after nil; with no such line, TEXT is the last
paragraph's and :after is t.  Raises an `sns-roam:' error for a DATE
that is not YYYY-MM-DD, for a note outside the reference layout (see
`sns-roam--history-body' and `sns-roam--check-history-run'), or when
TEXT is the text of two paragraphs.  Pure."
  (unless (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date)
    (sns-roam--signal-bad-date date))
  (let* ((texts (mapcar #'org-ml-to-trimmed-string
                        (sns-roam--history-body top-level-children)))
         (dates (mapcar #'sns-roam--history-line-date texts))
         (_ (sns-roam--check-history-run dates))
         (position (seq-position dates date
                                 (lambda (line-date new-date)
                                   (and line-date
                                        (not (string< new-date line-date))))))
         (anchor (if position (nth position texts) (car (last texts)))))
    (let ((count (seq-count (lambda (text) (string= text anchor)) texts)))
      (when (> count 1)
        (sns-roam--signal-match-count count 'sns-roam-history-anchor anchor)))
    (list :anchor anchor :after (null position))))

(defun sns-roam-history-anchor (id date)
  "Return where a history line dated DATE goes in reference note ID.

Returns:
  (:id ID :file FILE :anchor TEXT :after BOOL)

TEXT is the trimmed text of the first history line dated on or
before DATE, with :after nil, so the new line goes before it.  With
no such line, TEXT is the last paragraph's and :after is t.  Pass
TEXT and :after to `sns-roam-insert-element' with a predicate that
compares `org-ml-to-trimmed-string' to TEXT.  The note is parsed
from the buffer `find-file-noselect' returns, headings included.
Writes nothing.  Errors loudly on an unknown ID, a DATE that is not
YYYY-MM-DD, and a note outside the reference layout."
  (let ((file (sns-roam--node-file-or-error id)))
    (with-current-buffer (find-file-noselect file)
      (append (list :id id :file file)
              (sns-roam--call-with-context
               (list :id id :file file)
               (lambda ()
                 ;; Choose from all of the history, even when the
                 ;; owner has narrowed the note.
                 (sns-roam--history-anchor-in
                  (org-ml-get-children (save-restriction
                                         (widen)
                                         (org-ml-parse-this-buffer)))
                  date)))))))

(defun sns-roam--upsert-keyword (section key value)
  "Return SECTION with KEY's keyword set to VALUE.
Replaces existing keyword in place; appends if absent."
  (let* ((children (org-ml-get-children section))
         (found    nil)
         (updated  (mapcar
                    (lambda (c)
                      (if (and (org-ml-is-type 'keyword c)
                               (string= (org-ml-get-property :key c) key))
                          (progn
                            (setq found t)
                            (org-ml-set-property :value value c))
                        c))
                    children)))
    (org-ml-set-children
     (if found
         updated
       (append updated (list (org-ml-build-keyword key value))))
     section)))

(defun sns-roam-set-keyword (id key value)
  "Set #+KEY: VALUE in the top-level section of roam node ID.

KEY is the bare uppercase keyword name (e.g. \"TITLE\"); VALUE
is a string. Returns (:id :file :diff), as
`sns-roam--update-section' does.  Errors loudly on unknown ID
or missing top-level section."
  (sns-roam--update-section
   'sns-roam-set-keyword id
   (lambda (section)
     (sns-roam--upsert-keyword section key value))))

(sns-roam-define-error bad-tag "org would not read this as a tag"
  (tag))

(defconst sns-roam--whole-tag-regexp (concat "\\`" org-tag-re "\\'")
  "Match a string that is one whole org tag, as `org-tag-re' allows.")

(defun sns-roam--check-tags (tags)
  "Return TAGS when org reads each one as a tag.
Raises `sns-roam-bad-tag' with the first tag that is not a string
matching `org-tag-re' in full.  Pure."
  (when-let* ((bad-tag (seq-find (lambda (tag)
                                   (not (and (stringp tag)
                                             (string-match-p sns-roam--whole-tag-regexp
                                                             tag))))
                                 tags)))
    (sns-roam--signal-bad-tag bad-tag))
  tags)

(defun sns-roam--filetags-value (tags)
  "Return the =#+filetags:= value for TAGS, a non-empty list: \":t1:t2:\".  Pure."
  (concat ":" (string-join tags ":") ":"))

(defun sns-roam--keyword-p (key element)
  "Non-nil if ELEMENT is a keyword whose parsed key is KEY, such as \"TITLE\"."
  (and (org-ml-is-type 'keyword element)
       (string= key (org-ml-get-property :key element))))

(defun sns-roam--set-filetags-in-section (section tags)
  "Return SECTION with one FILETAGS keyword holding TAGS, right after TITLE.
A FILETAGS keyword straight after the TITLE keyword keeps its place
and takes the new value; every other FILETAGS keyword is dropped.
With no such keyword, a new one follows TITLE and takes TITLE's blank
lines.  With TAGS nil, the keyword after TITLE goes and TITLE takes
its blank lines.  Maps over the full child list.  Raises
`sns-roam-bad-tag' for a tag org would not read, and
`sns-roam-malformed-note' when SECTION has no TITLE keyword.  Pure."
  (sns-roam--check-tags tags)
  (let* ((children (org-ml-get-children section))
         (title (or (seq-find (apply-partially #'sns-roam--keyword-p "TITLE")
                              children)
                    (sns-roam--signal-malformed-note 'title nil nil "TITLE")))
         (after-title (cadr (memq title children)))
         (tags-under-title (and after-title
                                (sns-roam--keyword-p "FILETAGS" after-title)
                                after-title))
         (title-blank-lines (org-ml-get-property :post-blank title)))
    (sns-roam--map-children
     (lambda (section-children)
       (mapcan
        (lambda (child)
          (cond
           ((eq child title)
            (cond
             ;; The line under the title is kept or removed in its own
             ;; clause below; removing it hands its blank lines back.
             (tags-under-title
              (list (if tags
                        child
                      (org-ml-set-property
                       :post-blank
                       (+ title-blank-lines
                          (org-ml-get-property :post-blank tags-under-title))
                       child))))
             (tags
              (list (org-ml-set-property :post-blank 0 child)
                    (org-ml-build-keyword "FILETAGS" (sns-roam--filetags-value tags)
                                          :post-blank title-blank-lines)))
             (t (list child))))
           ((eq child tags-under-title)
            (and tags
                 (list (org-ml-set-property :value (sns-roam--filetags-value tags)
                                            child))))
           ((sns-roam--keyword-p "FILETAGS" child) nil)
           (t (list child))))
        section-children))
     section)))

(defun sns-roam-set-tags (id tags)
  "Set the file tags of roam node ID to TAGS, a list of strings.

Writes one #+filetags: :t1:t2: line directly under #+title: and
removes any other #+filetags: line in the first section; with TAGS
nil, removes the line.  Returns (:id :file :diff), as
`sns-roam--update-section' does.  Errors loudly, before anything is
written, on a tag org would not read as a tag, on unknown ID, and on
a note with no #+title: line."
  (sns-roam--update-section
   'sns-roam-set-tags id
   (lambda (section)
     (sns-roam--set-filetags-in-section section tags))))

(defun sns-roam--split-roam-filename (path)
  "Return (PREFIX . SLUG) from a roam filename PATH.
PREFIX is the 14-digit timestamp + dash; SLUG is the body
between dash and =.org=. Errors if PATH doesn't match the
expected shape."
  (let ((name (file-name-nondirectory path)))
    (unless (string-match "^\\([0-9]\\{14\\}-\\)\\(.+\\)\\.org$" name)
      (sns-roam--signal-malformed-note 'roam-filename nil path nil name))
    (cons (match-string 1 name) (match-string 2 name))))

(defun sns-roam-rename-file (id new-slug)
  "Rename roam node ID's file to use NEW-SLUG, preserving the timestamp prefix.

Returns the new absolute path. Errors if ID is unknown, the
filename doesn't match the expected =TIMESTAMP-SLUG.org= shape,
or the destination already exists."
  (let* ((old-path (sns-roam--node-file-or-error id))
         (dir      (file-name-directory old-path))
         (parts    (sns-roam--call-with-context
                    (list :id id)
                    (lambda () (sns-roam--split-roam-filename old-path))))
         (prefix   (car parts))
         (new-name (concat prefix new-slug ".org"))
         (new-path (expand-file-name new-name dir)))
    (when (file-exists-p new-path)
      (sns-roam--signal-file-exists id new-path))
    (when (string= old-path new-path)
      (sns-roam--signal-file-exists id new-path new-slug))
    (let ((buf (find-buffer-visiting old-path)))
      (rename-file old-path new-path)
      (when buf
        (with-current-buffer buf
          (set-visited-file-name new-path nil t))))
    new-path))

(defun sns-roam-rename (id new-title)
  "Rewrite roam node ID's title to NEW-TITLE and rename its file to match.

Slug derivation uses `org-roam-node-slug' for parity with the
capture template. Returns a plist (:id :title :file :diff), where
:diff is the title change `sns-roam-set-keyword' made, labelled with
the file's name before the rename."
  (let* ((title-write (sns-roam-set-keyword id "TITLE" new-title))
         (node        (org-roam-node-from-id id))
         (_           (unless node
                        (sns-roam--signal-unknown-id id)))
         (slug        (org-roam-node-slug node))
         (new-path    (sns-roam-rename-file id slug)))
    (list :id id :title new-title :file new-path
          :diff (plist-get title-write :diff))))

(defun sns-roam--org-timestamp-of (time)
  "Return TIME as an inactive Org timestamp string,
matching the capture template's =%U= output (e.g. \"[2026-05-31 Sun 09:14]\").
TIME is an emacs internal time value (as produced by
`current-time', `encode-time', `parse-iso8601-time-string', etc.)."
  (format-time-string "[%Y-%m-%d %a %H:%M]" time))

(defun sns-roam--filename-prefix-of (time)
  "Return TIME as a 14-digit YYYYMMDDhhmmss filename prefix.
TIME is an emacs internal time value."
  (format-time-string "%Y%m%d%H%M%S" time))

(defun sns-roam--build-header-properties (id created kind aliases)
  "Return the list of =node-property= elements for a roam header.
ALIASES is a list of strings; when non-empty an extra
=ROAM_ALIASES= property is appended."
  (let ((base (list (org-ml-build-node-property "ID" id)
                    (org-ml-build-node-property "CREATED" created)
                    (org-ml-build-node-property "KIND" kind))))
    (if aliases
        (append base
                (list (org-ml-build-node-property
                       "ROAM_ALIASES"
                       (mapconcat (lambda (a) (format "\"%s\"" a))
                                  aliases " "))))
      base)))

(defun sns-roam--registered-file (id)
  "Return the file the org-roam database holds for node ID, or nil.
Resolves through `org-roam-node-from-id', as the edit primitives do."
  (let ((node (org-roam-node-from-id id)))
    (when node
      (org-roam-node-file node))))

(defun sns-roam--separate-body-elements (elements)
  "Return ELEMENTS with a blank line after each one but the last.
`org-ml-build-paragraph' gives a paragraph a :post-blank of 0, so
built paragraphs written in a row share no blank line and org reads
them as one paragraph. An element that already asks for more blank
lines keeps them. The last element is left alone, so no blank line
appears before the first headline, as `sns-roam-set-body' writes it."
  (append (mapcar (lambda (element)
                    (org-ml-set-property
                     :post-blank
                     (max 1 (org-ml-get-property :post-blank element))
                     element))
                  (butlast elements))
          (last elements)))

(defun sns-roam--new-note-content (note)
  "Return the text of a new roam file for NOTE, a plist of resolved values.
NOTE holds :id, :title, :kind, :created (an inactive timestamp
string), :aliases (a list of strings), :tags (a list of valid tags)
and :elements (the body, as org-ml nodes).  The file opens with one
section: the property drawer, #+title:, a #+filetags: line when
:tags is non-empty, and every body element before the first
headline.  The headlines follow as its siblings.  Pure."
  (cl-destructuring-bind (&key id title kind created aliases tags elements)
      note
    (let* ((drawer (apply #'org-ml-build-property-drawer
                          (sns-roam--build-header-properties id created kind aliases)))
           (header (append (list drawer (org-ml-build-keyword "title" title))
                           (when tags
                             (list (org-ml-build-keyword
                                    "filetags" (sns-roam--filetags-value tags))))))
           ;; Body paragraphs and lists share the header's section; the
           ;; first headline and everything after it sit beside it.
           (first-headline (or (cl-position-if
                                (lambda (element) (org-ml-is-type 'headline element))
                                elements)
                               (length elements)))
           (section (apply #'org-ml-build-section
                           (append header
                                   (sns-roam--separate-body-elements
                                    (cl-subseq elements 0 first-headline))))))
      (mapconcat #'org-ml-to-string
                 (cons section (cl-subseq elements first-headline))
                 ""))))

(defun sns-roam-create-node (title kind &optional elements id aliases created-time slug-source tags)
  "Create a new roam node with TITLE and KIND, returning a plist.

Slugifies TITLE for the filename, writes the file under
`org-roam-directory' with the standard roam header (:ID,
:CREATED, :KIND, optional :ROAM_ALIASES:, #+title) followed by
ELEMENTS — a list of org-ml AST nodes forming the body. ID, if
nil, is freshly generated via `org-id-new'. ALIASES is an
optional list of strings; when non-empty written as
:ROAM_ALIASES: per org-roam convention. CREATED-TIME, if
non-nil, is an emacs internal time value used in place of
`current-time' for both the :CREATED: property and the
filename's 14-digit prefix; both outputs are formatted from the
same time value. SLUG-SOURCE, if non-nil, is slugified for the
filename in place of TITLE — use it to decouple the filename slug
from a title that carries extra detail (e.g. an appended date),
so the file stays cleanly named while the title remains human.
TAGS, if non-nil, is a list of strings written as one
#+filetags: :t1:t2: line directly under #+title.
Indexes the new file in the org-roam database, so the edit
primitives can resolve the returned ID at once.
Returns (:id :title :file). Errors before writing anything if a
tag is not one org reads as a tag, if the destination exists, or
if the database holds ID for another file.
Errors after indexing if ID does not resolve to the new file."
  (sns-roam--check-tags tags)
  (let* ((id       (or id (org-id-new)))
         (slug     (org-roam-node-slugify (or slug-source title)))
         (prefix   (sns-roam--filename-prefix-of created-time))
         (filename (concat prefix "-" slug ".org"))
         (path     (expand-file-name filename org-roam-directory))
         (content  (sns-roam--new-note-content
                    (list :id id :title title :kind kind
                          :created (sns-roam--org-timestamp-of created-time)
                          :aliases aliases :tags tags :elements elements))))
    (when (file-exists-p path)
      (sns-roam--signal-file-exists id path))
    ;; org-roam only warns when it indexes a node whose ID another
    ;; file already holds, and the ID keeps resolving to that file.
    ;; Refuse before writing, so a retried batch that reuses a
    ;; pre-minted ID cannot leave a second file claiming it.
    (let ((registered (sns-roam--registered-file id)))
      (when registered
        (sns-roam--signal-id-conflict id registered path)))
    (with-temp-buffer
      (insert content)
      (write-region (point-min) (point-max) path nil 'silent))
    ;; The edit primitives look IDs up in the database, so a node
    ;; that is only on disk is unknown to them until it is indexed.
    (org-roam-db-update-file path)
    ;; Indexing reports some failures only as warnings, so check that
    ;; the ID now resolves to the new file before reporting success.
    (let ((registered (sns-roam--registered-file id)))
      (unless (and registered (file-equal-p registered path))
        (sns-roam--signal-index-failure id path registered)))
    (list :id id :title title :file path)))

(defun sns-roam--meeting-title (series time)
  "Return the title for a meeting-note instance of SERIES at TIME.
Appends an ISO date so instances are distinguishable in the
node-find picker while sharing a series name. Pure."
  (format "%s %s" series (format-time-string "%Y-%m-%d" time)))

(defun sns-roam-meeting-note (series)
  "Create a dated note instance for a recurring meeting SERIES.

SERIES is the stable series name (e.g. \"alan-smithee-1-1\",
\"pir-prep\", \"incident-review\"). The new node's title is
SERIES with today's date appended (\"alan-smithee-1-1 2026-06-16\")
so each occurrence is a distinct, picker-distinguishable node;
the filename slug derives from the bare SERIES, so the file is
not double-dated (org already supplies the timestamp prefix).
KIND is \"fleeting\" — raw meeting capture, to be mined into
permanent notes later. Always creates a fresh instance — never
finds an existing node — so identical series names never
collide. Opens the new file for editing.

Returns the create plist (:id :title :file)."
  (interactive
   (list (read-string "Recurring meeting series (e.g. alan-smithee-1-1): ")))
  (let* ((trimmed (string-trim series)))
    (when (string-empty-p trimmed)
      (user-error "sns-roam-meeting-note: empty series name"))
    (let* ((now    (current-time))
           (title  (sns-roam--meeting-title trimmed now))
           (result (sns-roam-create-node title "fleeting" nil nil nil now trimmed)))
      (find-file (plist-get result :file))
      result)))

(provide 'sns-roam-api)
;;; sns-roam-api.el ends here
