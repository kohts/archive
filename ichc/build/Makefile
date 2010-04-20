PWD := $(shell pwd)

# pdf name customization
PDF = "${PWD}/../ladygina-kohts - ichc - 1935.pdf"

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

all: html pdf

.PHONY : html fo pdf gen-plates clean all-clean

${DOCBOOK_BASE}/photoplates.docbook: ${DOCBOOK_BASE}/photoplates.raw ${TOOLS}/gen-figures-ichc.pl
	${TOOLS}/gen-figures-ichc.pl ${DOCBOOK_BASE}/photoplates.raw > ${DOCBOOK_BASE}/photoplates.docbook

${DOCBOOK_BASE}/photoplates_eng.docbook: ${DOCBOOK_BASE}/photoplates_eng.raw ${TOOLS}/gen-figures-ichc.pl
	${TOOLS}/gen-figures-ichc.pl ${DOCBOOK_BASE}/photoplates_eng.raw eng table > ${DOCBOOK_BASE}/photoplates_eng.docbook

${DOCBOOK_BASE}/photoplates_eng_print.docbook: ${DOCBOOK_BASE}/photoplates_eng.raw ${TOOLS}/gen-figures-ichc.pl
	${TOOLS}/gen-figures-ichc.pl ${DOCBOOK_BASE}/photoplates_eng.raw eng table formalpara > ${DOCBOOK_BASE}/photoplates_eng_print.docbook

${DOCBOOK_BASE}/drawings_eng.docbook: ${DOCBOOK_BASE}/drawings_eng.raw ${TOOLS}/gen-figures-ichc.pl
	${TOOLS}/gen-figures-ichc.pl ${DOCBOOK_BASE}/drawings_eng.raw eng tabler figure > ${DOCBOOK_BASE}/drawings_eng.docbook
	
${DOCBOOK_BASE}/drawings_eng_print.docbook: ${DOCBOOK_BASE}/drawings_eng.raw ${TOOLS}/gen-figures-ichc.pl
	${TOOLS}/gen-figures-ichc.pl ${DOCBOOK_BASE}/drawings_eng.raw eng tabler formalpara > ${DOCBOOK_BASE}/drawings_eng_print.docbook

gen-plates: $(DOCBOOK_BASE)/photoplates*.docbook $(DOCBOOK_BASE)/drawings*.docbook

html: ${STAMPS}/html
${STAMPS}/html: docbook-html-chunked.xsl $(DOCBOOK)
	mkdir -p ${HTML_BASE}
	cd ${HTML_BASE} && ( if [ ! -h images ] && [ -d ../images ] ; then ln -s ../images ; fi )
	cd ${DOCBOOK_BASE} && xsltproc --stringparam 'base.dir' ${HTML_BASE}/ ${PWD}/docbook-html-chunked.xsl ${MASTER}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/html

fo: ${STAMPS}/fo
${STAMPS}/fo: docbook-fo.xsl $(DOCBOOK) $(IMAGES_PRINT)
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index.fo ${PWD}/docbook-fo.xsl ${MASTER_PRINT}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/fo

pdf: ${STAMPS}/pdf
${STAMPS}/pdf: ${STAMPS}/fo
	mkdir -p $(FOP_BASE)
	cd $(FOP_BASE) && ( if [ ! -h fop-hyph.jar ] ; then ln -s ../../fonts/fop-hyph.jar ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fop.xconf ] ; then ln -s ../../fonts/fop.xconf ; fi )
	cd $(FOP_BASE) && ( if [ ! -h fonts ] ; then ln -s ../../fonts/fonts ; fi )
	cd ${FOP_BASE} && ( if [ ! -h images ] && [ -d ../images ] ; then ln -s ../images ; fi )
	cd ${FOP_BASE} && \
	export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
	/root/fop/trunk/fop --execdebug -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/pdf

clean:
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
