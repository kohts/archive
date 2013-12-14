KOHTS_BASE ?= /var/www

BOOK_DIR = afk-works
BOOK_NAME = "kohts - works"
_PDF_NAME = ${BOOK_NAME}.pdf

FONTS = ${KOHTS_BASE}/FONTS
TOOLS = ${KOHTS_BASE}/tools

SOURCE_BASE = ${KOHTS_BASE}/SOURCE/${BOOK_DIR}
IMAGES_BASE = ${KOHTS_BASE}/IMAGES/${BOOK_DIR}
BUILD_BASE = ${KOHTS_BASE}/BUILD/${BOOK_DIR}

# pdf
IMAGES_PRINT = ${IMAGES_BASE}/pdf
PDF_OUTPUT = ${KOHTS_BASE}/OUT/${BOOK_DIR}/${_PDF_NAME}
RTF_OUTPUT = ${KOHTS_BASE}/OUT/${BOOK_DIR}/${BOOK_NAME}.rtf
TXT_OUTPUT = ${KOHTS_BASE}/OUT/${BOOK_DIR}/${BOOK_NAME}.txt

# html
HTML_BASE = ${KOHTS_BASE}/OUT/${BOOK_DIR}/html

# source
DOCBOOK_BASE = ${SOURCE_BASE}/docbook
DOCBOOK = ${DOCBOOK_BASE}/*.docbook
MASTER = main.docbook
MASTER_PRINT = main_print.docbook
MASTER_RTF = main_rtf.docbook

# temp
FO_BASE = ${BUILD_BASE}/fo
FOP_BASE = ${BUILD_BASE}/fop
STAMPS = ${BUILD_BASE}/stamps

# make html and pdf output by default
all: html pdf

.PHONY : html fo pdf gen-plates clean all-clean

html: ${STAMPS}/html
${STAMPS}/html: docbook-html-chunked.xsl $(DOCBOOK)
	mkdir -p ${HTML_BASE} ; mkdir -p ${IMAGES_BASE}/hires ; mkdir -p ${IMAGES_BASE}/html ; mkdir -p ${IMAGES_PRINT}
	if [ ! -e ${KOHTS_BASE}/OUT/${BOOK_DIR}/images ] ; then ln -s ${KOHTS_BASE}/IMAGES/${BOOK_DIR} ${KOHTS_BASE}/OUT/${BOOK_DIR}/images ; fi
	cd ${HTML_BASE} && ( if [ ! -h images ] && [ -d ../images ] ; then ln -s ../images . ; fi )
	cd ${DOCBOOK_BASE} && xsltproc --xinclude \
	  --stringparam 'base.dir' ${HTML_BASE}/ \
	  `[ -e ${DOCBOOK_BASE}/book.css ] && echo "--stringparam html.stylesheet book.css"` \
	  ${SOURCE_BASE}/build/docbook-html-chunked.xsl ${MASTER}
	if [ -e $(DOCBOOK_BASE)/book.css ] ; then cp -f $(DOCBOOK_BASE)/book.css $(HTML_BASE)/book.css ; fi
	mkdir -p ${STAMPS}
	touch ${STAMPS}/html

fo: ${STAMPS}/fo
${STAMPS}/fo: docbook-fo.xsl $(DOCBOOK) $(IMAGES_PRINT)
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index.fo ${SOURCE_BASE}/build/docbook-fo.xsl ${MASTER_PRINT}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/fo

fo-rtf: ${STAMPS}/fo-rtf
${STAMPS}/fo-rtf: docbook-fo.xsl $(DOCBOOK) $(IMAGES_PRINT)
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index-rtf.fo ${SOURCE_BASE}/build/docbook-fo.xsl ${MASTER_RTF}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/fo

pdf: ${STAMPS}/pdf
${STAMPS}/pdf: ${STAMPS}/fo
	mkdir -p $(FOP_BASE)
	cd $(FOP_BASE) && ( if [ ! -h fop-hyph.jar ] ; then ln -s ${FONTS}/fop-hyph.jar ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fop.xconf ] ; then ln -s ${FONTS}/fop.xconf ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fonts ] ; then ln -s ${FONTS}/fonts ; fi )
	cd ${FOP_BASE} && ( if [ ! -h images ] && [ -d ${IMAGES_BASE} ] ; then ln -s ${IMAGES_BASE} images ; fi )
	cd ${FOP_BASE} && \
	export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
	  fop -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF_OUTPUT}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/pdf

pdfname:
	@echo $(_PDF_NAME)

rtf: ${STAMPS}/rtf
${STAMPS}/rtf: ${STAMPS}/fo-rtf
	mkdir -p $(FOP_BASE)
	cd $(FOP_BASE) && ( if [ ! -h fop-hyph.jar ] ; then ln -s ${FONTS}/fop-hyph.jar ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fop.xconf ] ; then ln -s ${FONTS}/fop.xconf ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fonts ] ; then ln -s ${FONTS}/fonts ; fi )
	cd ${FOP_BASE} && ( if [ ! -h images ] && [ -d ${IMAGES_BASE} ] ; then ln -s ${IMAGES_BASE} images ; fi )
	cd ${FOP_BASE} && \
	export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
	  /root/fop/trunk/fop -c fop.xconf ${FO_BASE}/index-rtf.fo -rtf ${RTF_OUTPUT}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/rtf

txt: ${STAMPS}/txt
${STAMPS}/txt: ${STAMPS}/fo
	mkdir -p $(FOP_BASE)
	cd $(FOP_BASE) && ( if [ ! -h fop-hyph.jar ] ; then ln -s ${FONTS}/fop-hyph.jar ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fop.xconf ] ; then ln -s ${FONTS}/fop.xconf ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fonts ] ; then ln -s ${FONTS}/fonts ; fi )
	cd ${FOP_BASE} && ( if [ ! -h images ] && [ -d ${IMAGES_BASE} ] ; then ln -s ${IMAGES_BASE} images ; fi )
	cd ${FOP_BASE} && \
	export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
	  /root/fop/trunk/fop -c fop.xconf ${FO_BASE}/index.fo -out text/plain ${TXT_OUTPUT}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/txt

clean:
	mkdir -p ${STAMPS}
	rm -f ${STAMPS}/*

clean-html:
	rm -rf ${HTML_BASE}
	rm -f ${STAMPS}/html

clean-pdf:
	rm -rf ${FO_BASE}
	rm -f ${STAMPS}/fo
	rm -f ${STAMPS}/pdf

clean-text:
	rm -f ${STAMPS}/txt
	rm -f ${STAMPS}/rtf

all-clean: clean-html clean-pdf clean-text clean 
