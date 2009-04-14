PWD := $(shell pwd)

DOCBOOK_BASE = ${PWD}/../docbook
DOCBOOK = ${DOCBOOK_BASE}/*.docbook
MASTER = main.docbook
MASTER_PRINT = main_print.docbook
IMAGES_PRINT = ${DOCBOOK_BASE}/../images/pdf/*.jpg
TOOLS = ${PWD}/../tools

HTML_BASE = ${PWD}/../html-onechunk
HTML_CHUNKED_BASE = ${PWD}/../html
FO_BASE = ${PWD}/../fo
PDF = "${PWD}/../ladygina-kohts - ichc - 1935.pdf"
FOP_BASE = ${PWD}/../fop

all: html pdf
all-html: html html-onechunk

${DOCBOOK_BASE}/photoplates.docbook: ${DOCBOOK_BASE}/photoplates.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/photoplates.raw > ${DOCBOOK_BASE}/photoplates.docbook

${DOCBOOK_BASE}/photoplates_eng.docbook: ${DOCBOOK_BASE}/photoplates_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/photoplates_eng.raw eng table > ${DOCBOOK_BASE}/photoplates_eng.docbook

${DOCBOOK_BASE}/photoplates_eng_print.docbook: ${DOCBOOK_BASE}/photoplates_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/photoplates_eng.raw eng table formalpara > ${DOCBOOK_BASE}/photoplates_eng_print.docbook

${DOCBOOK_BASE}/drawings_eng.docbook: ${DOCBOOK_BASE}/drawings_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/drawings_eng.raw eng tabler figure > ${DOCBOOK_BASE}/drawings_eng.docbook
	
${DOCBOOK_BASE}/drawings_eng_print.docbook: ${DOCBOOK_BASE}/drawings_eng.raw ${TOOLS}/gen-figures.pl
	${TOOLS}/gen-figures.pl ${DOCBOOK_BASE}/drawings_eng.raw eng tabler formalpara > ${DOCBOOK_BASE}/drawings_eng_print.docbook

html-onechunk: docbook-html-onechunk.xsl $(DOCBOOK)
	mkdir -p ${HTML_BASE}
	cd ${HTML_BASE} && ( if [ ! -h images ] ; then ln -s ../images ; fi )
	cd ${DOCBOOK_BASE} && xsltproc -o ${HTML_BASE}/index.html ${PWD}/docbook-html-onechunk.xsl ${MASTER}
	touch html-onechunk

html: docbook-html-chunked.xsl $(DOCBOOK)
	mkdir -p ${HTML_CHUNKED_BASE}
	cd ${HTML_CHUNKED_BASE} && ( if [ ! -h images ] ; then ln -s ../images ; fi )
	cd ${DOCBOOK_BASE} && xsltproc --stringparam 'base.dir' ${HTML_CHUNKED_BASE}/ ${PWD}/docbook-html-chunked.xsl ${MASTER}
	touch html

fo: docbook-fo.xsl $(DOCBOOK) $(IMAGES_PRINT)
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index.fo ${PWD}/docbook-fo.xsl ${MASTER_PRINT}
	touch fo

pdf: fo ${FOP_BASE}/fop.xconf
	cd ${FOP_BASE} && ( if [ ! -h images ] ; then ln -s ../images ; fi )
	cd ${FOP_BASE} && \
	export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
	/root/fop-0.95/fop --execdebug -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}
	touch pdf

clean-all-html: clean-html clean-html-onechunk
clean-html:
	rm -rf ${HTML_BASE}
	rm -r html
clean-html-onechunk:
	rm -rf ${HTML_CHUNKED_BASE}
	rm -r html-onechunk

clean-fo:
	rm -rf ${FO_BASE}
	rm -r fo
clean-pdf: clean-fo
#	rm -rf ${PDF}
	rm -r pdf

clean-status:
	rm -f html
	rm -f html-onechunk
	rm -f fo
	rm -f pdf

.PHONY : clean pdf gen-plates
clean: clean-all-html clean-pdf
gen-plates: $(DOCBOOK_BASE)/photoplates*.docbook $(DOCBOOK_BASE)/drawings*.docbook
