<?xml version="1.0" encoding="utf-8"?> 
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fo="http://www.w3.org/1999/XSL/Format"
  >

  <xsl:import href="/usr/share/xml/docbook/stylesheet/nwalsh/fo/docbook.xsl"/>
  
  <xsl:param name="chunker.output.encoding" select="'utf-8'"/>
  <xsl:param name="base.dir">fo/</xsl:param>
  <xsl:param name="body.font.family" select="'Arial'"/>
  <xsl:param name="title.font.family" select="'Arial'"/>
  <xsl:param name="monospace.font.family" select="'Courier New'"/>
  <xsl:param name="paper.type" select="'A4'"/>
  
  <xsl:param name="draft.mode">no</xsl:param>
<!--  <xsl:param name="draft.watermark.image">images/draft.png</xsl:param> -->

  <xsl:template match="processing-instruction('page-break')">
    <fo:block break-after="page" />
  </xsl:template>
  
  <xsl:param name="use.role.for.mediaobject" select="1"></xsl:param>

</xsl:stylesheet>
