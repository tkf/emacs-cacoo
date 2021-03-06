;;; cacoo-plugins.el --- plugins for cacoo.el

;; Copyright (C) 2010, 2011  SAKURAI Masashi

;; Author: SAKURAI Masashi <m.sakurai atmark kiwanami.net>
;; Keywords: 

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file defines some plugins for cacoo.el.

;; * How to define a plugin

;; The arguments of the plugin functions.
;; - start : the start point of the current image markup
;; - end : the end point of the current image markup
;; - content : the inner text of the current image markup
;; The return value should be 
;; - nil : the plugin ignores this markup text
;; - a cons cell ([cacoo:$img object] . [a function returns a deferred task that generates an image file]

;;; Code:

(setq cacoo:plugins nil)

;; ** Diagrams generated by the web services
;; [img:* (url) (filename) (size:option)]
;; content
;; <<<
;; The place holder '<<<' in the URL text is replaced by the content text with the URL encoding.

;; Ex [latex math formula]:
;; [img:* http://maru.bonyari.jp/texclip/render.php/texclip20100511002527.png?s=<<<&f=c&r=300&m=p&b=f texclip1.png 600]
;; \begin{align*}
;; f(a,b)=\int_a^b\frac{1+x}{a+x^2+x^3}dx
;; \end{align*}
;; <<<


(defvar cacoo:plugin-long-url-regexp
      "^\\* \\([^ \n\r\t]+\\) \\([^ \n\r\t]+\\)\\( [0-9]+\\)?")
(defvar cacoo:plugin-long-url-terminator "<<<")

(defun cacoo:plugin-long-url (start end content)
  (when (string-match cacoo:plugin-long-url-regexp content)
    (let ((url (match-string 1 content))
          (filename (match-string 2 content))
          (size (match-string 3 content)))
      (cacoo:plugin-long-url-gen 
       start end content url filename size))))

(push 'cacoo:plugin-long-url cacoo:plugins)

(defun cacoo:plugin-long-url-gen (start end content url filename size)
  (save-excursion
    (goto-char end)
    (and (re-search-forward cacoo:plugin-long-url-terminator)
         (let*
             ((t-start (match-beginning 0))
              (t-end (match-end 0))
              (text (buffer-substring (1+ end) (1- t-start)))
              (rurl 
               (replace-regexp-in-string 
                cacoo:plugin-long-url-terminator
                (cacoo:plugin-url-encode-string text) url)))
           (cons
            (make-cacoo:$img
             :url (cacoo:plugin-url-create 'long-url filename)
             :start start :end t-end
             :size (cacoo:aif size (string-to-number it) 
                     cacoo:max-size))
            (lexical-let ((rurl rurl) (filename filename))
              (lambda ()
                (deferred:$
                  (cacoo:http-get-d
                   rurl (cacoo:get-cache-path filename))))))))))

(defun cacoo:plugin-url-encode-string (str)
  (let ((array (string-to-vector str)))
    (mapconcat 'identity
     (loop for i from 0 below (length array)
           for ch = (aref array i)
           collect
           (cond
            ((eq ch ?\n) "%0D%0A")
            ((string-match "[-a-zA-Z0-9_:/.]" (char-to-string ch))
             (char-to-string ch))
            (t
             (format "%%%02X" ch)))) nil)))

;; ** UML diagrams
;; [img:UML (filename) (size:option)]
;; UML text (See samples at http://yuml.me/)
;; <<<

(defvar cacoo:plugin-class-regexp "^UML \\([^ \n\r\t]+\\)\\( [0-9]+\\)?")

(defun cacoo:plugin-class-diagram (start end content)
  (when (string-match cacoo:plugin-class-regexp content)
    (let ((url "http://yuml.me/diagram/scruffy/class/<<<")
          (filename (match-string 1 content))
          (size (match-string 2 content)))
      (cacoo:plugin-long-url-gen 
       start end content url filename size))))

(push 'cacoo:plugin-class-diagram cacoo:plugins)

;; ** Sequence diagrams in UML
;; [img:SEQ (filename) (size:option)]
;; Sequence diagram text (See samples at http://www.websequencediagrams.com/)
;; <<<

(defvar cacoo:plugin-seq-regexp "^SEQ \\([^ \n\r\t]+\\)\\( [0-9]+\\)?")

(defun cacoo:plugin-seq-diagram (start end content)
  (when (string-match cacoo:plugin-seq-regexp content)
    (let ((filename (match-string 1 content))
          (size (match-string 2 content)))
      (save-excursion
        (goto-char end)
        (and (re-search-forward cacoo:plugin-long-url-terminator)
             (let* ((t-start (match-beginning 0))
                    (t-end (match-end 0))
                    (text (buffer-substring (1+ end) (1- t-start))))
               (cons
                (make-cacoo:$img
                 :url (cacoo:plugin-url-create 'seq-diagram filename)
                 :start start :end t-end
                 :size (cacoo:aif size (string-to-number it)
                         cacoo:max-size))
                (lexical-let ((text text) (filename filename))
                  (lambda () (cacoo:plugin-seq-diagram-get 
                              text (cacoo:get-cache-path filename)))))))))))

(defun cacoo:plugin-seq-diagram-get (text filename)
  (lexical-let ((base-url "http://www.websequencediagrams.com/")
                (text text) (filename filename))
    (deferred:$
      (deferred:url-post base-url `((message ,text) (style "default")))
      (deferred:nextc it
        (lambda (buf)
          (let* ((line (unwind-protect
                           (with-current-buffer buf (buffer-string))
                         (kill-buffer buf)))
                 (url (if (string-match "\\?img=[a-zA-Z0-9]+" line)
                          (concat base-url (match-string 0 line)))))
            (cacoo:log "seq-diagram[%s] : GET -> %s" filename url)
            (cacoo:http-get-d url filename))))
      (deferred:watch it
        (lambda () (cacoo:log "seq-diagram[%s] : OK" filename))))))

(push 'cacoo:plugin-seq-diagram cacoo:plugins)

;; ** hatena fotolife
;; [f:id:(hatena id):(image id)(ext):image]
;; 
;; The following regexp is needed to use this plug-in:
;; (setq cacoo:img-regexp 
;;      '("\\[img:\\(.*\\)\\][^]\n\r]*$"
;;        "\\[f:\\(.*\\)\\][^]\n\t]*$"))

(defvar cacoo:plugin-hatena-fotolife-regexp
  "^\\id:\\([^:]+\\):\\([0-9]+\\)\\([jpg]\\):image")

(defun cacoo:plugin-hatena-fotolife (start end content)
  (when (string-match cacoo:plugin-hatena-fotolife-regexp content)
    (let* ((hatena-id (match-string 1 content))
           (image-id (match-string 2 content))
           (ext-id (match-string 3 content))
           (date-id (substring image-id 0 8))
           (ext-name 
            (cond
             ((equal "j" ext-id) "jpg")
             ((equal "p" ext-id) "png")
             ((equal "g" ext-id) "gif")
             (t (error "unknown ext-id [%s]" ext-id))))
           (url (format "http://f.hatena.ne.jp/images/fotolife/k/%s/%s/%s.%s" 
                        hatena-id date-id image-id ext-name))
           (filename (format "hatena-%s-%s.%s" hatena-id image-id ext-name)))
      (cons
       (make-cacoo:$img
        :url url :start start :end end
        :size cacoo:max-size)
       (lexical-let ((url url))
         (lambda () (cacoo:load-diagram-remote url)))))))

(push 'cacoo:plugin-hatena-fotolife cacoo:plugins)


;; ** Diagrams generated by the command line
;; [img:CMD "(command)" (filename) (size:option)]
;; argument file content
;; <<<
;; The place holder '%IN%' in the command line text is replaced by the temporary file name.
;; The place holder '%OUT%' in the content text is replaced by the output file name.

;; Ex [gnuplot]:
;; [img:CMD 'gnuplot %IN%' plot1.eps]
;; set term postscript eps
;; set output '%OUT%'
;; plot exp(-0.03*x*x)*sin(x)
;; <<<

(defvar cacoo:plugin-cmd-regexp
      "^CMD '\\([^']+\\)' \\([^ \t\r\n]+\\)\\( [0-9]+\\)?")
(defvar cacoo:plugin-cmd-terminator "<<<")

(defun cacoo:plugin-cmd (start end content)
  (when (string-match cacoo:plugin-cmd-regexp content)
    (let ((cmd (match-string 1 content))
          (filename (match-string 2 content))
          (size (match-string 3 content)))
      (cacoo:plugin-cmd-gen 
       start end content cmd filename size))))

(push 'cacoo:plugin-cmd cacoo:plugins)

(defun cacoo:plugin-cmd-gen (start end content cmd filename size)
  (save-excursion
    (goto-char end)
    (and (re-search-forward cacoo:plugin-cmd-terminator)
         (lexical-let* 
             ((t-start (match-beginning 0))
              (t-end (match-end 0)) (cmd cmd)
              (text (buffer-substring (1+ end) (1- t-start)))
              (output-path (cacoo:get-cache-path filename)))
           (cons
            (make-cacoo:$img
             :url (cacoo:plugin-url-create 'command filename)
             :start start :end t-end
             :size (cacoo:aif size (string-to-number it)
                     cacoo:max-size))
            (lambda () 
              (cacoo:plugin-cmd-exec-d cmd output-path text)))))))

(defun cacoo:plugin-cmd-replace-io (text in out)
  (replace-regexp-in-string 
   "%IN%" in (replace-regexp-in-string
              "%OUT%" out text t) t))

(defun cacoo:plugin-cmd-exec-d (cmd output-path text)
  (lexical-let*
      ((tmpfile (format "tmp_%s.txt" (file-name-nondirectory output-path)))
       (rcmd  (cacoo:plugin-cmd-replace-io cmd  tmpfile output-path))
       (rtext (cacoo:plugin-cmd-replace-io text tmpfile output-path))
       (output-path output-path))
    (deferred:$
      (deferred:next
        (lambda (x) (write-region rtext nil tmpfile)))
      (deferred:process-shellc it rcmd)
      (deferred:nextc it 
        (lambda (x) 
          (cacoo:log "CMD EXE[%s] return value -> [%s]" rcmd x)
          (ignore-errors (delete-file tmpfile))
          (unless (cacoo:file-exists-p output-path)
            (error "Can not create the output file : %s" output-path)))))))

;; ** Graphviz diagram
;; [img:DOT (filename) (size:option)]
;; dot format (http://www.graphviz.org/)
;; <<<

(defvar cacoo:plugin-dot-regexp "^DOT \\([^ \n\r\t]+\\)\\( [0-9]+\\)?")

(defun cacoo:plugin-dot-diagram (start end content)
  (when (string-match cacoo:plugin-dot-regexp content)
    (let ((filename (match-string 1 content))
          (size (match-string 2 content)))
      (cacoo:plugin-cmd-gen 
       start end content "dot -Tpng %IN% -o %OUT%" filename size))))

(push 'cacoo:plugin-dot-diagram cacoo:plugins)


;; ** SVG
;; [img:SVG (filename) (size:option)]
;; SVG text
;; <<<

(defvar cacoo:plugin-svg-regexp "^SVG \\([^ \n\r\t]+\\)\\( [0-9]+\\)?")

(defun cacoo:plugin-svg (start end content)
  (when (string-match cacoo:plugin-svg-regexp content)
    (let ((filename (match-string 1 content))
          (size (match-string 2 content)))
      (save-excursion
        (goto-char end)
        (when (re-search-forward cacoo:plugin-cmd-terminator)
          (let* ((t-start (match-beginning 0))
                 (t-end (match-end 0))
                 (text (buffer-substring (1+ end) (1- t-start)))
                 (output-path (cacoo:get-cache-path filename)))
            (cons 
             (make-cacoo:$img
              :url (cacoo:plugin-url-create 'long-url filename)
              :start start :end t-end
              :size (cacoo:aif size (string-to-number it)
                      cacoo:max-size))
             (lexical-let ((text text) (output-path output-path))
               (lambda () 
                 (write-region text nil output-path)
                 (deferred:succeed))))))))))

(push 'cacoo:plugin-svg cacoo:plugins)

(provide 'cacoo-plugins)
;;; cacoo-plugins.el ends here
