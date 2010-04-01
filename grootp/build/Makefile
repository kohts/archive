PWD := $(shell pwd)

# pdf name customization
PDF = "${PWD}/../kohts - grootp - 1937.pdf"

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

.PHONY : html fo pdf clean all-clean

html: ${STAMPS}/html
${STAMPS}/html: docbook-html-chunked.xsl $(DOCBOOK)
	mkdir -p ${HTML_BASE}
	cd ${HTML_BASE} && ( if [ ! -h images ] && [ -d ../images ] ; then ln -s ../images ; fi )
	cd ${DOCBOOK_BASE} && xsltproc --xinclude --stringparam 'base.dir' ${HTML_BASE}/ ${PWD}/docbook-html-chunked.xsl ${MASTER}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/html

fo: ${STAMPS}/fo
${STAMPS}/fo: docbook-fo.xsl $(DOCBOOK) $(IMAGES_PRINT)
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index.fo ${PWD}/docbook-fo.xsl ${MASTER_PRINT}
	mkdir -p ${STAMPS}
	touch ${STAMPS}/fo

pdf: ${STAMPS}/pdf
${STAMPS}/pdf: ${STAMPS}/fo ${FOP_BASE}/fop.xconf
	cd ${FOP_BASE} && ( if [ ! -h images ] && [ -d ../images ] ; then ln -s ../images ; fi )
	cd ${FOP_BASE} && \
	export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
	fop -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}
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
