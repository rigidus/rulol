(defun g!-symbol-p (s)
  (and (symbolp s)
       (> (length (symbol-name s)) 2)
       (string= (symbol-name s)
                "G!"
                :start1 0
                :end1 2)))

(defun flatten (x)
  (labels ((rec (x acc)
             (cond ((null x) acc)
                   ((atom x) (cons x acc))
                   (t (rec
                       (car x)
                       (rec (cdr x) acc))))))
    (rec x nil)))

(defvar forth-registers
  '(pstack rstack pc
    dict compiling dtable))

(defstruct forth-word
  name prev immediate thread)

(defun forth-lookup (w last)
  (if last
      (if (eql (forth-word-name last) w)
          last
          (forth-lookup
           w (forth-word-prev last)))))

(defmacro forth-inner-interpreter ()
  `(loop
      do (cond
           ((functionp (car pc))
            (funcall (car pc)))
           ((consp (car pc))
            (push (cdr pc) rstack)
            (setf pc (car pc)))
           ((null pc)
            (setf pc (pop rstack)))
           (t
            (push (car pc) pstack)
            (setf pc (cdr pc))))
      until (and (null pc) (null rstack))))

(defvar forth-prim-forms nil)

(defmacro def-forth-naked-prim (&rest code)
  `(push ',code forth-prim-forms))

(defmacro def-forth-prim (&rest code)
  `(def-forth-naked-prim
       ,@code
       (setf pc (cdr pc))))

(def-forth-prim nop nil)

(def-forth-prim * nil
  (push (* (pop pstack) (pop pstack))
        pstack))

(def-forth-prim drop nil
  (pop pstack))

(def-forth-prim dup nil
  (push (car pstack) pstack))

(def-forth-prim swap nil
  (rotatef (car pstack) (cadr pstack)))

(def-forth-prim print nil
  (print (pop pstack)))

(def-forth-prim >r nil
  (push (pop pstack) rstack))

(def-forth-prim r> nil
  (push (pop rstack) pstack))

(defmacro alet% (letargs &rest body)
  `(let ((this) ,@letargs)
     (setq this ,@(last body))
     ,@(butlast body)
     this))

(defmacro alet (letargs &rest body)
  `(let ((this) ,@letargs)
     (setq this ,@(last body))
     ,@(butlast body)
     (lambda (&rest params)
       (apply this params))))

(defun mkstr (&rest args)
  (with-output-to-string (s)
    (dolist (a args) (princ a s))))


(defun symb (&rest args)
  (values (intern (apply #'mkstr args))))


(defun |#`-reader| (stream sub-char numarg)
  (declare (ignore sub-char))
  (unless numarg (setq numarg 1))
  `(lambda ,(loop for i from 1 to numarg
               collect (symb 'a i))
     ,(funcall
       (get-macro-character #\`) stream nil)))

(set-dispatch-macro-character
 #\# #\` #'|#`-reader|)

(defun pandoriclet-get (letargs)
  `(case sym
     ,@(mapcar #`((,(car a1)) ,(car a1))
               letargs)
     (t (error
         "Unknown pandoric get: ~a"
         sym))))

(defun pandoriclet-set (letargs)
  `(case sym
     ,@(mapcar #`((,(car a1))
                  (setq ,(car a1) val))
               letargs)
     (t (error
         "Unknown pandoric set: ~a"
         sym val))))

(defun o!-symbol-p (s)
  (and (symbolp s)
       (> (length (symbol-name s)) 2)
       (string= (symbol-name s)
                "O!"
                :start1 0
                :end1 2)))

(defun o!-symbol-to-g!-symbol (s)
  (symb "G!"
        (subseq (symbol-name s) 2)))

(defmacro defmacro/g! (name args &rest body)
  (let ((syms (remove-duplicates
               (remove-if-not #'g!-symbol-p
                              (flatten body)))))
    `(defmacro ,name ,args
       (let ,(mapcar
              (lambda (s)
                `(,s (gensym ,(subseq
                               (symbol-name s)
                               2))))
              syms)
         ,@body))))


(defmacro defmacro! (name args &rest body)
  (let* ((os (remove-if-not #'o!-symbol-p args))
         (gs (mapcar #'o!-symbol-to-g!-symbol os)))
    `(defmacro/g! ,name ,args
       `(let ,(mapcar #'list (list ,@gs) (list ,@os))
          ,(progn ,@body)))))


(defmacro! dlambda (&rest ds)
  `(lambda (&rest ,g!args)
     (case (car ,g!args)
       ,@(mapcar
          (lambda (d)
            `(,(if (eq t (car d))
                   t
                   (list (car d)))
               (apply (lambda ,@(cdr d))
                      ,(if (eq t (car d))
                           g!args
                           `(cdr ,g!args)))))
          ds))))

(defmacro plambda (largs pargs &rest body)
  (let ((pargs (mapcar #'list pargs)))
    `(let (this self)
       (setq
        this (lambda ,largs ,@body)
        self (dlambda
              (:pandoric-get (sym)
                             ,(pandoriclet-get pargs))
              (:pandoric-set (sym val)
                             ,(pandoriclet-set pargs))
              (t (&rest args)
                 (apply this args)))))))

;; Prim-form: (name immediate . forms)
(defmacro forth-install-prims ()
  `(progn
     ,@(mapcar
        #`(let ((thread (lambda ()
                          ,@(cddr a1))))
            (setf dict
                  (make-forth-word
                   :name ',(car a1)
                   :prev dict
                   :immediate ,(cadr a1)
                   :thread thread))
            (setf (gethash thread dtable)
                  ',(cddr a1)))
        forth-prim-forms)))

(defvar forth-stdlib nil)

(defmacro forth-stdlib-add (&rest all)
  `(setf forth-stdlib
         (nconc forth-stdlib
                ',all)))


(defmacro new-forth ()
  `(alet ,forth-registers
         (setq dtable (make-hash-table))
         (forth-install-prims)
         (dolist (v forth-stdlib)
           (funcall this v))
         (plambda (v) ,forth-registers
                  (let ((word (forth-lookup v dict)))
                    (if word
                        (forth-handle-found)
                        (forth-handle-not-found))))))

(defmacro! go-forth (o!forth &rest words)
  `(dolist (w ',words)
     (funcall ,g!forth w)))

(defvar my-forth (new-forth))

(def-forth-prim [ t ; <- t означает незамедлительность.
  (setf compiling nil))

(def-forth-prim ] nil ; <- не незамедлительность
  (setf compiling t))

(defmacro forth-compile-in (v)
  `(setf (forth-word-thread dict)
         (nconc (forth-word-thread dict)
                (list ,v))))

(defmacro forth-handle-found ()
  `(if (and compiling
            (not (forth-word-immediate word)))
       (forth-compile-in (forth-word-thread word))
       (progn
         (setf pc (list (forth-word-thread word)))
         (forth-inner-interpreter))))

(defmacro forth-handle-not-found ()
  `(cond
     ((and (consp v) (eq (car v) 'quote))
      (if compiling
          (forth-compile-in (cadr v))
          (push (cadr v) pstack)))
     ((and (consp v) (eq (car v) 'postpone))
      (let ((word (forth-lookup (cadr v) dict)))
        (if (not word)
            (error "Postpone failed: ~a" (cadr v)))
        (forth-compile-in (forth-word-thread word))))
     ((symbolp v)
      (error "Word ~a not found" v))
     (t
      (if compiling
          (forth-compile-in v)
          (push v pstack)))))

(def-forth-prim create nil
  (setf dict (make-forth-word :prev dict)))

(def-forth-prim name nil
  (setf (forth-word-name dict) (pop pstack)))

(def-forth-prim immediate nil
  (setf (forth-word-immediate dict) t))

(forth-stdlib-add
 create
 ] create ] [
 '{ name)

(forth-stdlib-add
 { (postpone [) [
 '} name immediate)

(def-forth-prim @ nil
    (push (car (pop pstack))
          pstack))

(def-forth-prim ! nil
  (let ((location (pop pstack)))
    (setf (car location) (pop pstack))))

(defmacro forth-unary-word-definer (&rest words)
  `(progn
     ,@(mapcar
        #`(def-forth-prim ,a1 nil
            (push (,a1 (pop pstack))
                  pstack))
        words)))

(defmacro! forth-binary-word-definer (&rest words)
  `(progn
     ,@(mapcar
        #`(def-forth-prim ,a1 nil
            (let ((,g!top (pop pstack)))
              (push (,a1 (pop pstack)
                         ,g!top)
                    pstack)))
        words)))

(forth-unary-word-definer
 not car cdr cadr caddr cadddr
 oddp evenp)
(forth-binary-word-definer
 eq equal + - / = < > <= >=
 max min and or)

(declaim (inline get-pandoric))

(defun get-pandoric (box sym)
  (funcall box :pandoric-get sym))

(defsetf get-pandoric (box sym) (val)
  `(progn
     (funcall ,box :pandoric-set ,sym ,val)
     ,val))

(defmacro! with-pandoric (syms o!box &rest body)
  `(symbol-macrolet
       (,@(mapcar #`(,a1 (get-pandoric ,g!box ',a1))
                  syms))
     ,@body))

(def-forth-naked-prim branch-if nil
  (setf pc (if (pop pstack)
               (cadr pc)
               (cddr pc))))

(forth-stdlib-add
 { r> drop } 'exit name)

(def-forth-naked-prim compile nil
  (setf (forth-word-thread dict)
        (nconc (forth-word-thread dict)
               (list (cadr pc))))
  (setf pc (cddr pc)))

(def-forth-prim here nil
  (push (last (forth-word-thread dict))
        pstack))

(forth-stdlib-add
 { compile not
 compile branch-if
 compile nop
 here } 'if name immediate)

(forth-stdlib-add
 { compile nop
 here swap ! } 'then name immediate)

(forth-stdlib-add
 { 0 swap - } 'negate name
 { dup 0 < if negate then } 'abs name)

(forth-stdlib-add
 { compile 't
 compile branch-if
 compile nop
 here swap
 compile nop
 here swap ! } 'else name immediate)

(forth-stdlib-add
 { evenp if 0 else 1 then } 'mod2 name)

(forth-stdlib-add
 { compile nop
 here } 'begin name immediate
 { compile 't
 compile branch-if
 compile nop
 here ! } 'again name immediate)

(defun get-forth-thread (forth word)
  (with-pandoric (dict) forth
                 (forth-word-thread
                  (forth-lookup word dict))))

(defun print-forth-thread (forth word)
  (let ((*print-circle* t))
    (print (get-forth-thread forth word))
    t))

(defmacro alambda (parms &body body)
  `(labels ((self ,parms ,@body))
     #'self))

(defmacro flubify-aux ()
  `(alambda (c)
            (if c
                (cond
                  ((gethash (car c) prim-ht)
                   (assemble-flub
                    `(funcall
                      ,(gethash (car c) prim-ht))
                    (self (cdr c))))
                  ((gethash (car c) thread-ht)
                   (assemble-flub
                    `(funcall #',(car (gethash (car c)
                                               thread-ht)))
                    (self (cdr c))))
                  ((eq (car c) branch-if)
                   (assemble-flub
                    `(if (pop pstack)
                         (go ,(gethash (cadr c) go-ht)))
                    (self (cddr c))))
                  ((consp (car c))
                   (flubify forth (car c) prim-ht
                            thread-ht branch-if)
                   (self c))
                  (t
                   (assemble-flub
                    `(push ',(car c) pstack)
                    (self (cdr c))))))))

(defmacro assemble-flub (form rest)
  `(if (gethash c go-ht)
       (list* (gethash c go-ht)
              ,form
              ,rest)
       (list* ,form
              ,rest)))

(defun flubify (forth thread prim-ht
                thread-ht branch-if)
  (unless #1=(gethash thread thread-ht)
          (setf #1# (list (gensym)))
          (let ((go-ht (make-hash-table)))
            (funcall
             (alambda (c)
                      (when c
                        (cond
                          ((eq (car c) branch-if)
                           (setf (gethash (cadr c) go-ht)
                                 (gensym))
                           (self (cddr c)))
                          ((consp (car c))
                           (flubify forth thread prim-ht
                                    thread-ht branch-if)))
                        (self (cdr c))))
             thread)
            (setf #1# (nconc #1# (funcall
                                  (flubify-aux)
                                  thread))))))

(defun compile-flubified (thread thread-ht)
  `(labels (,@(let (collect)
                   (maphash
                    (lambda (k v)
                      (declare (ignore k))
                      (push
                       `(,(car v) ()
                          (tagbody ,@(cdr v)))
                       collect))
                    thread-ht)
                   (nreverse collect)))
     (funcall #',(car (gethash thread thread-ht)))))

(defun flubify-thread-shaker
    (forth thread ht tmp-ht branch-if compile)
  (if (gethash thread tmp-ht)
      (return-from flubify-thread-shaker)
      (setf (gethash thread tmp-ht) t))
  (cond
    ((and (consp thread) (eq (car thread) branch-if))
     (if (cddr thread)
         (flubify-thread-shaker
          forth (cddr thread) ht
          tmp-ht branch-if compile)))
    ((and (consp thread) (eq (car thread) compile))
     (error "Can't convert compiling word to lisp"))
    ((consp thread)
     (flubify-thread-shaker
      forth (car thread) ht
      tmp-ht branch-if compile)
     (if (cdr thread)
         (flubify-thread-shaker
          forth (cdr thread) ht
          tmp-ht branch-if compile)))
    ((not (gethash thread ht))
     (if (functionp thread)
         (setf (gethash thread ht)
               (with-pandoric (dtable) forth
                              (gethash thread dtable)))))))

(defun forth-to-lisp (forth word)
  (let ((thread (get-forth-thread forth word))
        (shaker-ht (make-hash-table))
        (prim-ht (make-hash-table))
        (thread-ht (make-hash-table))
        (branch-if (get-forth-thread forth 'branch-if))
        (compile (get-forth-thread forth 'compile)))
    (flubify-thread-shaker
     forth thread shaker-ht
     (make-hash-table) branch-if compile)
    (maphash (lambda (k v)
               (declare (ignore v))
               (setf (gethash k prim-ht) (gensym)))
             shaker-ht)
    (flubify forth thread prim-ht thread-ht branch-if)
    `(let (pstack)
       (let (,@(let (collect)
                    (maphash
                     (lambda (k v)
                       (push `(,(gethash k prim-ht)
                                (lambda () ,@(butlast v)))
                             collect))
                     shaker-ht)
                    (nreverse collect)))
         ,(compile-flubified
           thread thread-ht)))))
