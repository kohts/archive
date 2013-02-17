<?xml version="1.0" encoding="utf-8"?> 
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fo="http://www.w3.org/1999/XSL/Format"
  >

<!-- effectively defines the output produced by this xsl;
this is for FO output, used to produce PDF with Apache FOP. -->
<xsl:import href="/usr/share/xml/docbook/stylesheet/nwalsh/fo/docbook.xsl"/>

<xsl:param name="arial_font_size">
  <xsl:value-of select="$body.font.master * 0.8"/>
  <xsl:text>pt</xsl:text>
</xsl:param>
<xsl:template match="para[@role='Arial']">
  <fo:block font-family="Arial" font-weight="normal" font-size="{$arial_font_size}">
    <xsl:apply-templates/>
  </fo:block>
</xsl:template>
<xsl:template match="quote[@role='Arial']">
  <fo:inline font-family="Arial" font-weight="normal" font-style="italic" font-size="{$arial_font_size}">
    <xsl:apply-templates/>
  </fo:inline>
</xsl:template>
<xsl:template match="inline[@role='Arial']">
  <fo:inline font-family="Arial" font-weight="normal" font-style="normal" font-size="{$arial_font_size}">
    <xsl:apply-templates/>
  </fo:inline>
</xsl:template>


<xsl:param name="fop1.extensions" select="1"></xsl:param>

<!-- body width; valid only for FOP -->
<xsl:param name="body.start.indent">0pt</xsl:param>
<xsl:param name="title.margin.left">-4pt</xsl:param>

<!-- page header
http://docbook.sourceforge.net/release/xsl/current/doc/fo/header.column.widths.html -->
<xsl:param name="header.column.widths">1 3 1</xsl:param>

<xsl:param name="toc.section.depth">1</xsl:param>
<xsl:param name="generate.toc">
book      toc,title,figure,table,example,equation
</xsl:param>

<xsl:attribute-set name="formal.object.properties">
   <xsl:attribute name="keep-together.within-column">auto</xsl:attribute>
</xsl:attribute-set>
  
<xsl:param name="details_font_size">
  <xsl:value-of select="$body.font.master * 0.8"/>
  <xsl:text>pt</xsl:text>
</xsl:param>
<xsl:param name="figure_font_size">
  <xsl:value-of select="$body.font.master * 0.8"/>
  <xsl:text>pt</xsl:text>
</xsl:param>
<xsl:template match="para[@role='details']">
  <fo:block font-size="{$details_font_size}">
    <xsl:apply-templates/>
  </fo:block>
</xsl:template>
<xsl:template match="para[@role='figure']">
  <fo:block font-size="{$figure_font_size}">
    <xsl:apply-templates/>
  </fo:block>
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
	    <l:template name="figure" text="Таблица %n"/>
	  </l:context>
	  <l:context name="xref-number-and-title">
        <l:template name="figure" text="Табл. %n"/>
	  </l:context>

	  <l:gentext key="Example" text="Фотоиллюстрация"/>
	  <l:gentext key="example" text="Фотоиллюстрация"/>
      <l:gentext key="ListofExamples" text="Перечень фототаблиц"/>
      <l:gentext key="listofexamples" text="Перечень фототаблиц"/>
	  <l:context name="title">
        <l:template name="example" text="Фототаблица %n. %t"/>
	  </l:context>
	  <l:context name="xref-number">
	    <l:template name="example" text="Фото %n"/>
	  </l:context>
	  <l:context name="xref-number-and-title">
	    <l:template name="example" text="Фото %n"/>
	  </l:context>

	  <l:gentext key="Equation" text="Кривая"/>
	  <l:gentext key="equation" text="Кривая"/>
      <l:gentext key="ListofEquations" text="Перечень кривых"/>
      <l:gentext key="listofequations" text="Перечень кривых"/>
	  <l:context name="title">
        <l:template name="equation" text="Кривая %n. %t"/>
	  </l:context>
	  <l:context name="xref-number">
	    <l:template name="equation" text="Кривая %n"/>
	  </l:context>
	  <l:context name="xref-number-and-title">
	    <l:template name="equation" text="Кривая %n"/>
	  </l:context>

  	</l:l10n>
  
    <l:l10n language="en">

	  <l:gentext key="Example" text="Photo"/>
	  <l:gentext key="example" text="Photo"/>
      <l:gentext key="ListofExamples" text="List of Photos"/>
      <l:gentext key="listofexamples" text="List of Photos"/>
	  <l:context name="title">
        <l:template name="example" text="Photo %n. %t"/>
	  </l:context>
	  <l:context name="xref-number">
	    <l:template name="example" text="Photo %n"/>
	  </l:context>
	  <l:context name="xref-number-and-title">
	    <l:template name="example" text="Photo %n"/>
	  </l:context>

  	</l:l10n>

  </l:i18n>
  
</xsl:stylesheet>
