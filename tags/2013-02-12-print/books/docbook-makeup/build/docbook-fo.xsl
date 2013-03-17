<?xml version="1.0" encoding="utf-8"?> 
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fo="http://www.w3.org/1999/XSL/Format"
  >

  <xsl:import href="/usr/share/xml/docbook/stylesheet/nwalsh/fo/docbook.xsl"/>

<xsl:attribute-set name="formal.object.properties">
   <xsl:attribute name="keep-together.within-column">auto</xsl:attribute>
</xsl:attribute-set>
  
<xsl:param name="details_font_size">
  <xsl:value-of select="$body.font.master * 0.8"/>
  <xsl:text>pt</xsl:text>
</xsl:param>
<xsl:template match="para[@role='details']">
  <fo:block font-size="{$details_font_size}">
    <xsl:apply-templates/>
  </fo:block>
</xsl:template>

<xsl:template match="cihc_age">
<xsl:if test="(@y) and (@y != '0')">
  <xsl:value-of select="@y"/><xsl:text> </xsl:text>
  <xsl:choose>
    <xsl:when test="(../../@lang = 'en')">y.</xsl:when>
    <xsl:otherwise>г.</xsl:otherwise>
  </xsl:choose>
  <xsl:text> </xsl:text>
</xsl:if>
<xsl:value-of select="@m"/><xsl:text> </xsl:text>
<xsl:choose>
  <xsl:when test="(../../@lang = 'en')">m.</xsl:when>
  <xsl:otherwise>м.</xsl:otherwise>
</xsl:choose>
<xsl:if test="(@d) and (@d != '0')">
  <xsl:text> </xsl:text><xsl:value-of select="@d"/><xsl:text> </xsl:text>
  <xsl:choose>
    <xsl:when test="(../../@lang = 'en')">d.</xsl:when>
    <xsl:otherwise>д.</xsl:otherwise>
  </xsl:choose>
</xsl:if>
</xsl:template>

<xsl:template match="processing-instruction('br')"><fo:block/></xsl:template>
<xsl:template match="processing-instruction('page-break')">
  <fo:block break-after="page" />
</xsl:template>
  
  <xsl:param name="chunker.output.encoding" select="'utf-8'"/>
  <xsl:param name="base.dir">fo/</xsl:param>
  <xsl:param name="body.font.family" select="'Literaturnaya'"/>
  <xsl:param name="title.font.family" select="'Literaturnaya'"/>
  <xsl:param name="monospace.font.family" select="'Courier New'"/>
  <xsl:param name="paper.type" select="'A4'"/>
  
  <xsl:param name="draft.mode">no</xsl:param>
<!--  <xsl:param name="draft.watermark.image">images/draft.png</xsl:param> -->

<xsl:param name="generate.toc">
book      toc,title,figure,table,example,equation
</xsl:param>

  <xsl:param name="use.role.for.mediaobject" select="1"></xsl:param>

  <xsl:param name="local.l10n.xml" select="document('')"/>
  <l:i18n xmlns:l="http://docbook.sourceforge.net/xmlns/l10n/1.0">
    <l:l10n language="ru">

	  <l:gentext key="Figure" text="Таблица"/>
	  <l:gentext key="figure" text="Таблица"/>
      <l:gentext key="ListofFigures" text="Список рисунков"/>
      <l:gentext key="listoffigures" text="Список рисунков"/>
      <l:context name="title">
	    <l:template name="figure" text="Таблица %n. %t"/>
	  </l:context>
	  <l:context name="xref-number">
	    <l:template name="figure" text="Таблица %n"/>
	  </l:context>
	  <l:context name="xref-number-and-title">
        <l:template name="figure" text="Табл. %n"/>
	  </l:context>

	  <l:gentext key="Example" text="Фотоиллюстрация"/>
	  <l:gentext key="example" text="Фотоиллюстрация"/>
      <l:gentext key="ListofExamples" text="Список фотоиллюстраций"/>
      <l:gentext key="listofexamples" text="Список фотоиллюстраций"/>
	  <l:context name="title">
        <l:template name="example" text="Табл. %n. %t"/>
	  </l:context>
	  <l:context name="xref-number">
	    <l:template name="example" text="Табл. %n"/>
	  </l:context>
	  <l:context name="xref-number-and-title">
	    <l:template name="example" text="Табл. %n"/>
	  </l:context>

	</l:l10n>
  </l:i18n>
  
</xsl:stylesheet>