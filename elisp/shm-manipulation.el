;;; shm-manipulation.el --- Manipulation of nodes commands

;; Copyright (c) 2014 Chris Done. All rights reserved.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'shm-layout)

(defun shm/split ()
  "Split the current thing into two parts.

Strings: \"x|y\" -> \"x\" \"y\"
"
  (interactive)
  (cond
   ((shm-in-string)
    (insert "\" \"")
    (forward-char -2))))

(defun shm/$ ()
  "Swap parens with a dollar."
  (interactive)
  (let* ((current-pair (shm-current-node-pair))
         (current (cdr current-pair)))
    (if (eq (shm-node-cons current) 'Paren)
        (progn (let ((child (shm-node-child current-pair)))
                 (shm-raise-to child current)
                 (if (looking-back " ")
                     nil
                   (shm-insert-string " "))
                 (shm-insert-string "$")
                 (if (looking-at " ")
                     nil
                   (shm-insert-string " ")))))))

(defun shm/add-operand ()
  "When in an infix application, figure out the operator and add
a new operand. E.g.

foo <> bar|

will give you

foo <> bar <> |

or

foo <> |bar

will give you

foo <> | <> bar

This is more convenient than typing out the same operator."
  (interactive)
  (let* ((current-pair (shm-current-node-pair))
         (current (cdr current-pair))
         (parent-pair (shm-node-parent current-pair))
         (parent (cdr parent-pair)))
    (cond
     ((eq 'InfixApp (shm-node-cons parent))
      (let ((qop
             (or (shm-get-qop-string (cdr (shm-node-previous current-pair)))
                 (shm-get-qop-string (cdr (shm-node-next current-pair))))))
        (cond
         (qop
          (cond
           ((= (point) (shm-node-start current))
            (let ((point (point)))
              (shm-insert-string (concat " " qop " "))
              (goto-char point)))
           ((= (point) (shm-node-end current))
            (shm-insert-string (concat " " qop " ")))
           (t (error "Please go to the start or end of the node to indicate direction."))))
         (t (error "Unable to figure out the operator.")))))
     ((string= "Type" (shm-node-type-name current))
      (if (= (point) (shm-node-start current))
          (save-excursion (insert " -> "))
        (insert " -> ")))
     (t (error "Not in an infix application.")))))

(defun shm/raise ()
  "Raise the expression up one, replacing its parent."
  (interactive)
  (let* ((current-pair (shm-current-node-pair))
         (current (cdr current-pair))
         (parent-pair (shm-node-parent current-pair (shm-node-type current)))
         (parent (cdr parent-pair))
         (actual-parent-pair (shm-node-parent current-pair)))
    (cond
     ((and parent
           (or (shm-node-app-p current)
               (eq (shm-node-cons current) 'TyFun))
           (shm-node-paren-p parent))
      (let* ((grandparent-pair (shm-node-parent parent-pair (shm-node-type current)))
             (grandparent (cdr grandparent-pair)))
        (when grandparent
          (shm-raise-to current grandparent))))
     (parent
      (when (string= (shm-node-type current)
                     (shm-node-type parent))
        (shm-raise-to current parent)))
     ((and (eq 'UnGuardedRhs (shm-node-cons (cdr actual-parent-pair)))
           (eq 'Lambda (shm-node-cons current)))
      (goto-char (shm-node-start current))
      (delete-char 1)
      (delete-region (point)
                     (search-backward-regexp "[ ]+=[ ]+"))
      (insert " ")
      (search-forward-regexp "[ ]*->")
      (delete-region (- (point) 2)
                     (search-forward-regexp "[ ]+"))
      (insert "= "))
     (t
      (error "No matching parent!")))))

(defun shm-raise-to (current parent)
  "Raise the current node and replace PARENT."
  (let ((shm/raise-code (shm-kill-node 'buffer-substring-no-properties current nil t)))
    (shm-kill-node 'buffer-substring-no-properties parent)
    (shm-insert-indented (lambda () (insert shm/raise-code)))
    (shm/reparse)))

(defun shm/splice ()
  "Splice the current children wrapped in parens into the parent.

foo (a b c) -> foo a b c

Only parenthesized nodes are supported at the moment."
  (interactive)
  (let* ((current-pair (shm-current-node-pair))
         (current (cdr current-pair))
         (parent-pair (shm-node-parent current-pair))
         (parent (cdr parent-pair)))
    (if (and parent (shm-node-paren-p parent))
        (shm-raise-to current parent)
      (message "Unsupported node type for splicing!"))))

(defun shm/split-list ()
  "Split the current list into two lists by the nearest comma."
  (interactive)
  (let ((current-pair (shm-current-node-pair)))
    (while (not (eq 'List (shm-node-cons (cdr (shm-node-parent current-pair)))))
      (setq current-pair (shm-node-parent current-pair)))
    (let ((current (cdr current-pair)))
      (cond
       ((< (abs (- (point) (shm-node-start current)))
           (abs (- (point) (shm-node-end current))))
        (goto-char (shm-node-start current))
        (when (looking-back ",")
          (delete-char -1)))
       (t
        (goto-char (shm-node-end current))
        (when (looking-at ",")
          (delete-char 1))))
      (insert "] ["))))

(defun shm/comment ()
  "Comment the current node, or if there is none, or some error,
  fall back to `comment-dwim'. If the region is active, uses
  `comment-dwim'."
  (interactive)
  (if (region-active-p)
      (call-interactively 'comment-dwim)
    (let ((current (shm-current-node)))
      (cond
       ((shm-in-comment)
        (save-excursion
          (unless (looking-at "{-")
            (search-backward-regexp "{-" nil nil 1))
          (delete-region (point) (+ 2 (point)))
          (search-forward-regexp "-}" nil nil 1)
          (delete-region (- (point) 2) (point))))
       (current
        (save-excursion
          (goto-char (shm-node-start current))
          (insert "{-")
          (goto-char (shm-node-end current))
          (insert "-}")
          (font-lock-fontify-region (shm-node-start current)
                                    (shm-node-end current))))
       (t (call-interactively 'comment-dwim))))))

(defun shm/qualify-import ()
  "Toggle the qualification of the import at point."
  (interactive)
  (save-excursion
    (let ((points (shm-decl-points)))
      (goto-char (car points))
      (shm/reparse)
      (let ((current (shm-current-node)))
        (when (and current
                   (string= "ImportDecl"
                            (shm-node-type-name current)))
          (cond
           ((looking-at "import[\n ]+qualified[ \n]+")
            (search-forward-regexp "qualified" (shm-node-end current) t 1)
            (delete-region (point)
                           (search-backward-regexp "qualified"))
            (just-one-space 1))
           (t
            (search-forward-regexp "import")
            (shm-insert-string " qualified")
            (just-one-space 1))))))))

(defun shm/bind-toggle ()
  "Swap the monadicness of a bind."
  (interactive)
  (let ((node (shm-get-binding-parent (shm-current-node-pair))))
    (case (shm-node-cons node)
      (Generator (progn (goto-char (shm-node-start node))
                        (search-forward " <- ")
                        (delete-region (- (point) (length " <- "))
                                       (point))
                        (insert " = ")
                        (goto-char (shm-node-start node))
                        (shm-insert-string "let ")))
      (LetStmt (progn (goto-char (shm-node-start node))
                      (delete-region (point) (+ (point) (length "let ")))
                      (search-forward " = ")
                      (delete-region (- (point) (length " = "))
                                     (point))
                      (insert " <- "))))))

(defun shm-get-binding-parent (node-pair)
  "Get the binding parent of the node."
  (if (or (eq 'Generator (shm-node-cons (cdr node-pair)))
          (eq 'LetStmt (shm-node-cons (cdr node-pair))))
      (cdr node-pair)
    (let ((parent-pair (shm-node-parent node-pair)))
      (if parent-pair
          (shm-get-binding-parent parent-pair)
        (error "Couldn't find a let/generator statement in the node's parents.")))))

(defun shm-push-current-data-constructor-down (&optional arg)
  "Transpose the current data constructor with the data
constructor ARG \"constructors\" below (wrap around if
necessary). Here's an example:

data Test = A | (point)B | C

=>

data Test = A | C | (point)B"
  (interactive)
  (setq arg (or arg 1))
  (let ((end (1- (length (shm-get-data-constructor-members-points))))
        (ind (shm-find-current-data-member-index-at-point)))
    (shm-transpose-data-constructors ind (mod (+ ind arg) end))))

(defun shm-push-current-data-constructor-up (&optional arg)
  "Transpose the current data constructor with the data
constructor ARG \"constructors\" above (wrap around if
necessary). Here's an example:

data Test = A | (point)B | C

=>

data Test = (point)B | A | C"
  (interactive)
  (setq arg (or arg 1))
  (let ((end (1- (length (shm-get-data-constructor-members-points))))
        (ind (shm-find-current-data-member-index-at-point)))
    (shm-transpose-data-constructors (mod (- ind arg) end) ind)))

(defun shm-in-data-constructor ()
  "Check if the current node is a Data Declaration (DataDecl) or
the child of one."
  (eq 'DataDecl (elt (elt (shm-decl-ast) 0) 1)))

(defun shm-get-data-constructor-members-points ()
  "Find the region bounds of all the data constructors within the
current data declaration."
  (when (shm-in-data-constructor)
    (mapcar (lambda (ps) (cons (elt ps 2) (elt ps 3)))
            (remove-if (lambda (n) (eq n 'nil))
                       (mapcar (lambda (c) (if (eq' ConDecl (elt c 1)) c nil))
                               (shm-decl-ast))))))

(defun shm-find-current-data-member-index-at-point ()
  "Find the index of the current data constructor with the
current data declaration."
  (let ((location (point)))
    (-find-index (lambda (bounds) (and
                              (>= (marker-position (cdr bounds)) location)
                              (<= (marker-position (car bounds)) location)))
                 (shm-get-data-constructor-members-points))))

(defun shm-transpose-data-constructors (m n)
  "Transpose the mth and nth data constructors. This function
will silently fail if the m or n are not valid indices (the first
index is 0). Here's an example of the function working as
intended. In this example, the 1st and 9th data constructors will
be swapped.

data JSValue
  = JSLetIn String
            JSValue
            JSValue
  | JSLambda [String]
             JSValue (**)
  | JSNull
  | JSIdentifier String
  | JSString String
  | JSArray [JSValue]
  | JSIndexInfo JSValue
                JSValue
  | JSApplication JSValue
                  [JSValue]
  | JSNumber Double
  | JSObject [(String, JSValue)] (**)

data JSValue
  = JSLetIn String
            JSValue
            JSValue
  | JSObject [(String, JSValue)] (**)
  | JSNull
  | JSIdentifier String
  | JSString String
  | JSArray [JSValue]
  | JSIndexInfo JSValue
                JSValue
  | JSApplication JSValue
                  [JSValue]
  | JSNumber Double
  | JSLambda [String]
             JSValue (**)"
  (let* ((bounds (bounds-of-thing-at-point 'defun))
         (regions (shm-get-data-constructor-members-points))
         (m1 (car (elt regions m)))
         (m2 (cdr (elt regions m)))
         (m3 (car (elt regions n)))
         (m4 (cdr (elt regions n))))
    (when (and (shm-in-data-constructor)
               (>= m 0)
               (>= n 0)
               (< n (length regions))
               (< m (length regions))
               (not (= m n)))
      ;; We need to move the point to the Ident node for the transposition to work correctly.
      (let ((x (elt (cdr (shm-current-node-pair)) 1)))
        (cond ((eq x 'DataDecl) (forward-word 1))
              ((eq x 'Ident) (forward-word 0))
              ((eq x 'ConDecl) (if (= (point) (shm-node-start (cdr (shm-current-node-pair))))
                                   (shm-set-node-overlay)
                                 (progn (shm/backward-node) (shm-set-node-overlay))))
              (t (progn
                   (while (not (eq 'ConDecl (elt (cdr (shm-current-node-pair)) 1)))
                     (shm/goto-parent))
                   (shm-set-node-overlay)))))
      (transpose-regions
       (marker-position m1)
       (marker-position m2)
       (marker-position m3)
       (marker-position m4))
      (let ((parsed-ast (shm-get-ast (if (bound-and-true-p structured-haskell-repl-mode)
                                         "stmt"
                                       "decl")
                                     (car bounds) (cdr bounds))))
        (let ((bail (lambda ()
                      (when shm-display-quarantine
                        (shm-quarantine-overlay (car bounds) (cdr bounds)))
                      (setq shm-lighter " SHM!")
                      nil)))
          (if parsed-ast
              (progn
                (when (bound-and-true-p structured-haskell-repl-mode)
                  (shm-font-lock-region (car bounds) (cdr bounds)))
                (let ((ast (shm-get-nodes parsed-ast (car bounds) (cdr bounds))))
                  (if ast
                      (progn (setq shm-lighter " SHM")
                             (set-marker m1 nil)
                             (set-marker m2 nil)
                             (set-marker m3 nil)
                             (set-marker m4 nil)
                             (shm-set-decl-ast (car bounds) ast)
                             (shm-delete-overlays (point-min) (point-max) 'shm-quarantine)
                               ;This was my initial guess for
                               ;silencing the message at the end. It
                               ;doesn't work.
                             (let ((inhibit-message t))
                               (shm/init)))
                    (funcall bail))))
            (funcall bail)))))))

(provide 'shm-manipulation)
