<?xml version="1.0" encoding="UTF-8"?>

<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:import href="/usr/share/xml/docbook/stylesheet/nwalsh/html/chunk.xsl"/>

<xsl:template match="para[@role='details']">
  <p><font size="-1">
    <xsl:apply-templates/>
  </font></p>
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

<xsl:template match="processing-instruction('br')"><br/></xsl:template>

<xsl:template match="processing-instruction('pre_b')">
  <pre style="background: #DADADA;"><xsl:value-of select="." /></pre>
</xsl:template>


<xsl:param name="chunker.output.encoding" select="'utf-8'"/>

<xsl:param name="toc.section.depth">1</xsl:param>
<xsl:param name="generate.toc">
appendix  title
article/appendix  nop
article   toc,title
book      toc,title,figure,table,example
chapter   toc,title
part      toc,title
preface   toc,title
qandadiv  toc
qandaset  toc
reference toc,title
sect1     title
sect2     toc
sect3     toc
sect4     toc
sect5     toc
section   toc
set       toc,title
</xsl:param>

<!--<xsl:param name="generate.toc">
book      toc,title,figure,table,example,equation
part      toc,title
</xsl:param>
-->
  
  <xsl:param name="local.l10n.xml" select="document('')"/>
  <l:i18n xmlns:l="http://docbook.sourceforge.net/xmlns/l10n/1.0">
    <l:l10n language="ru">

	  <l:gentext key="Figure" text="Таблица"/>
	  <l:gentext key="figure" text="Таблица"/>
      <l:gentext key="ListofFigures" text="Список рисунков"/>
      <l:gentext key="listoffigures" text="Список рисунков"/>
      <l:context name="title">
	    <l:template name="figure" text="Рисунок %n. %t"/>
	  </l:context>
	  <l:context name="xref-number">
	    <l:template name="figure" text="Рисунок %n"/>
	  </l:context>
	  <l:context name="xref-number-and-title">
        <l:template name="figure" text="Рис. %n"/>
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

