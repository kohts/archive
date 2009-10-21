PWD := $(shell pwd)

# pdf name customization
PDF = "${PWD}/../ladygina-kohts - mnm - 1928.pdf"

# everything else should work by default
DOCBOOK_BASE = ${PWD}/../docbook
DOCBOOK = ${DOCBOOK_BASE}/*.docbook
MASTER = main.docbook
MASTER_PRINT = main_print.docbook
IMAGES_PRINT = ${DOCBOOK_BASE}/../images/pdf/*.jpg
TOOLS = ${PWD}/../tools

HTML_BASE = ${PWD}/../html
FO_BASE = ${PWD}/../fo
FOP_BASE = ${PWD}/../fop

STAMPS = ${PWD}/../stamps

# make html and pdf output by default
all: html pdf

.PHONY : html fo pdf gen-plates clean all-clean

${DOCBOOK_BASE}/photoplates_eng.docbook: ${DOCBOOK_BASE}/photoplates_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/photoplates_eng.raw eng photo > ${DOCBOOK_BASE}/photoplates_eng.docbook
${DOCBOOK_BASE}/pictures_eng.docbook: ${DOCBOOK_BASE}/pictures_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/pictures_eng.raw eng picture figure --no-page-break > ${DOCBOOK_BASE}/pictures_eng.docbook

${DOCBOOK_BASE}/photoplates_eng_print.docbook: ${DOCBOOK_BASE}/photoplates_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/photoplates_eng.raw eng photo formalpara > ${DOCBOOK_BASE}/photoplates_eng_print.docbook
${DOCBOOK_BASE}/pictures_eng_print.docbook: ${DOCBOOK_BASE}/pictures_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/pictures_eng.raw eng picture formalpara figure --no-page-break > ${DOCBOOK_BASE}/pictures_eng_print.docbook

${DOCBOOK_BASE}/curves_eng_print.docbook: ${DOCBOOK_BASE}/curves_eng.docbook ${TOOLS}/conv_curves.pl
	${TOOLS}/conv_curves.pl ${DOCBOOK_BASE}/curves_eng.docbook > ${DOCBOOK_BASE}/curves_eng_print.docbook

gen-plates: $(DOCBOOK_BASE)/photoplates*.docbook

html: ${STAMPS}/html
${STAMPS}/html: docbook-html-chunked.xsl $(DOCBOOK)
	mkdir -p ${HTML_BASE}
	cd ${HTML_BASE} && ( if [ ! -h images ] && [ -d ../images ] ; then ln -s ../images ; fi )
	cd ${DOCBOOK_BASE} && xsltproc --xinclude \
	  --stringparam 'base.dir' ${HTML_BASE}/ \
	  --stringparam html.stylesheet book.css \
	  ${PWD}/docbook-html-chunked.xsl ${MASTER}
	cp -f $(DOCBOOK_BASE)/book.css $(HTML_BASE)/book.css
	mkdir -p ${STAMPS}
	touch ${STAMPS}/html

fo: ${STAMPS}/fo
${STAMPS}/fo: docbook-fo.xsl $(DOCBOOK)
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index.fo ${PWD}/docbook-fo.xsl ${MASTER_PRINT}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/fo

pdf: ${STAMPS}/pdf
${STAMPS}/pdf: ${STAMPS}/fo ${FOP_BASE}/fop.xconf
	cd ${FOP_BASE} && ( if [ ! -h images ] && [ -d ../images ] ; then ln -s ../images ; fi )
	cd ${FOP_BASE} && \
	export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
	/root/fop-trunk/trunk/fop --execdebug -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}
	#/root/fop-0.95/fop --execdebug -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}
	#fop -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/pdf

clean:
	touch -r /etc/passwd ${DOCBOOK_BASE}/photoplates_eng.docbook
	touch -r /etc/passwd ${DOCBOOK_BASE}/photoplates_eng_print.docbook
	touch -r /etc/passwd ${DOCBOOK_BASE}/pictures_eng.docbook
	touch -r /etc/passwd ${DOCBOOK_BASE}/pictures_eng_print.docbook
	touch -r /etc/passwd ${DOCBOOK_BASE}/curves_eng_print.docbook
	mkdir -p ${STAMPS}
	rm -f ${STAMPS}/*

clean-html:
	rm -rf ${HTML_BASE}
	rm -f ${STAMPS}/html

clean-pdf:
	rm -rf ${FO_BASE}
	rm -rf ${PDF}
	rm -f ${STAMPS}/fo
	rm -f ${STAMPS}/pdf

all-clean: clean-html clean-pdf clean
