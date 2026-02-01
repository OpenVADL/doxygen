/******************************************************************************
 *
 * Copyright (C) 1997-2021 by Dimitri van Heesch.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation under the terms of the GNU General Public License is hereby
 * granted. No representations are made about the suitability of this software
 * for any purpose. It is provided "as is" without express or implied warranty.
 * See the GNU General Public License for more details.
 *
 * Documents produced by Doxygen are derivative works derived from the
 * input used in their production; they are not affected by this license.
 *
 */

%option never-interactive
%option prefix="cocorcodeYY"
%option noyywrap
%option reentrant
%option extra-type="struct cocorcodeYY_state *"
%top{
#include <stdint.h>
}

%{




#include "cocorcode.h"
#include "code.h"
#include "config.h"

#include <unordered_map>
#include <unordered_set>

#include <stdio.h>
#include "doxygen.h"
#include "message.h"
#include "outputgen.h"
#include "outputlist.h"
#include "filedef.h"
#include "message.h"
#include "tooltip.h"
#include "util.h"
#include "memberdef.h"
#include "definition.h"
#include "debug.h"
#include "membername.h"
#include "searchindex.h"
#include "arguments.h"
#include "config.h"
#include "groupdef.h"
#include "classlist.h"
#include "filedef.h"
#include "filename.h"
#include "namespacedef.h"
#include "tooltip.h"
#include "scopedtypevariant.h"
#include "symbolresolver.h"
#include "dir.h"
#include "debug.h"
#include "moduledef.h"

#define YY_NEVER_INTERACTIVE 1
#define YY_NO_INPUT 1
#define YY_NO_UNISTD_H 1

#define CODIFY(style) \
    startFontClass(yyscanner,style); \
    yyextra->code->codify(yytext); \
    endFontClass(yyscanner);

#define USE_STATE2STRING 0

struct cocorcodeYY_state{
     OutputCodeList *                                       code;
     std::unordered_map< std::string, ScopedTypeVariant >   codeClassMap;
     StringVector                                           curClassBases;
     bool                                                   insideCodeLine = FALSE;
     int                                                    anchorCount = 0;

     const char   *                                         inputString;     //!< the code fragment as text
     yy_size_t                                              inputPosition;   //!< read offset during parsing
     int                                                    inputLines;      //!< number of line in the code fragment
     int                                                    yyLineNr;        //!< current line number
     bool                                                   needsTermination;

     bool                                                   lineNumbers      = FALSE;
     const Definition   *                                   searchCtx;
     bool                                                   collectXRefs     = FALSE;

     int                                                    lastContext      = 0;
     int                                                    lastSemanticActionContext  = 0;
     int                                                    docBlockContext  = 0;
     int                                                    partsDefined     = 0;
     int                                                    depth            = 0;

     QCString                                               scope;

     std::vector<int>                                       scopeNameLengthStack;

     const FileDef    *                                     sourceFileDef;
     std::unique_ptr<FileDef>                               exampleFileDef;
     VariableContext                                        theVarContext;
     const Definition *                                     currentDefinition;
     const MemberDef  *                                     currentMemberDef;
     bool                                                   includeCodeFragment;
     const char   *                                         currentFontClass;
     bool                                                   insideSpecialComment;
     TooltipManager                                         tooltipManager;
};

#if USE_STATE2STRING
static const char *stateToString(int state);
#endif

static void setCurrentDoc(yyscan_t yyscanner,const QCString &anchor);
static void addToSearchIndex(yyscan_t yyscanner,const QCString &text);
static void startCodeLine(yyscan_t yyscanner);
static void endCodeLine(yyscan_t yyscanner);
static void nextCodeLine(yyscan_t yyscanner);
static void codifyLines(yyscan_t yyscanner,const QCString &text);
static bool getLinkInScope(yyscan_t yyscanner,const QCString &c,  // scope
                           const QCString &m,  // member
                           const QCString &memberText, // exact text
                           OutputCodeList &ol,
                           const QCString &text,
                           bool varOnly=FALSE
                          );
static bool getLink(yyscan_t yyscanner,const QCString &className,
                    const QCString &memberName,
                    OutputCodeList &ol,
                    const QCString &text=QCString(),
                    bool varOnly=FALSE);
static void generateGlobalLink(yyscan_t yyscanner,OutputCodeList &ol,const QCString &clName,
                                      bool typeOnly=FALSE,bool varOnly=FALSE);
static void generateRuleLink(yyscan_t yyscanner, OutputCodeList &ol,
                                const char *funcName);
static void startFontClass(yyscan_t yyscanner,const char *s,bool specialComment=false);
static void endFontClass(yyscan_t yyscanner,bool specialComment=false);
static int countLines(yyscan_t yyscanner);
static yy_size_t yyread(yyscan_t yyscanner,char *buf,yy_size_t max_size);

static std::mutex g_searchIndexMutex;
static std::mutex g_docCrossReferenceMutex;

#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) result=yyread(yyscanner,buf,max_size);

%}
LETTER        [A-Z]|[a-z]|_
DIGIT         [0-9]
STRINGCHAR    [^\"\\\r\n]
CHARCHAR      [^'\\\r\n]
ESCAPE        \\["'\\abfnrtv0]
UNICODE       \\u[0-9a-fA-F]{4}
WS            [ \t\r\n]
HEXDIGIT      ([0-9]|[a-f])

s             {WS}*

STRING        \"({STRINGCHAR}|{ESCAPE}|{UNICODE})*\" 
CHAR          \'({CHARCHAR}|{ESCAPE}|{UNICODE})\'
IDENT         {LETTER}({LETTER}|{DIGIT}|_)*

%x SemanticAction
%x VariableDefinition
%x FunctionDefinition

%x JavaImport
%x CSharpImport
%x CPlusPlusImport

%x Top
%x GrammarDef
%x Annotation
%x Attribute
%x Production
%x FileIdExtraction
%x CommentDecl
%x WhitespaceDecl
%x End


%x LineComment
%x BlockComment

%x SkipLineComment
%x SkipBlockComment

%%

 /* Semantic Action*/
<*>"(."                                 {
                                          yyextra->lastSemanticActionContext = YY_START;
                                          BEGIN(SemanticAction);
                                        }

<SemanticAction>{
  ".)"                                  BEGIN(yyextra->lastSemanticActionContext);
  {CHAR}                                ; // Overrides the <*> 
  {STRING}                              ; // Overrides the <*> 
  .                                     ;
}
 /* Comment handling */

<*>\r                                   ; // Does nothing, e.g not included in the output

<SkipLineComment>{
    [^\n]+                              ; // Does nothing, e.g not included in the output
    \n                                  {
                                          yyextra->yyLineNr++;
                                          BEGIN(yyextra->docBlockContext);
                                        }
}
<SkipBlockComment>{
    "\n"                                yyextra->yyLineNr++;
    [^*\n]+                             ; // Does nothing, e.g not included in the output
    "*"+/[^/]                           ; // Does nothing, e.g not included in the output
    "*/"                                BEGIN(yyextra->docBlockContext);
}

<LineComment>{
    [^\n]+                              { yyextra->code->codify(yytext); }
    \n                                  {
                                          codifyLines(yyscanner, yytext);
                                          endFontClass(yyscanner);
                                          BEGIN(yyextra->docBlockContext);
                                        }
}
<BlockComment>{
    [^*\n]+                             yyextra->code->codify(yytext);
    "*"+/[^/]                           yyextra->code->codify(yytext);
    "*/"                                {
                                          yyextra->code->codify(yytext);
                                          endFontClass(yyscanner);
                                          BEGIN(yyextra->docBlockContext);
                                        }
}

 /* Import handling */
<JavaImport>{
  "static"                              CODIFY("keyword");
  ";"                                   {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Top);
                                        }
}

<CSharpImport>{
  ";"                                   {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Top);
                                        }
}

<CPlusPlusImport>{
  "<"[^>]+">"                           {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Top);
                                        }
  "\""[^"]+"\""                         {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Top);
                                        }
}

 /* Grammar */


<Top>{
  "@"                                   {
                                          CODIFY("preprocessor");
                                          BEGIN(Annotation);
                                        }
  "{"                                   { 
                                          yyextra->code->codify(yytext);
                                          BEGIN(FunctionDefinition);
                                        }
  "$"{IDENT}"="{IDENT}("."{IDENT})*     yyextra->code->codify(yytext);
  "import"                              {
                                          yyextra->code->codify(yytext);
                                          BEGIN(JavaImport);
                                        }
  "using"                               {
                                          yyextra->code->codify(yytext);
                                          BEGIN(CSharpImport);
                                        }
  "#include"                            {
                                          yyextra->code->codify(yytext);
                                          BEGIN(CPlusPlusImport);
                                        }
  "COMPILER"                            {
                                          CODIFY("keyword");
                                          BEGIN(GrammarDef);
                                        }
  "CHARACTERS"                          |
  "TOKENS"                              |
  "PRAGMAS"                             |
  "PRODUCTIONS"                         CODIFY("keyword");
  "COMMENTS FROM"                       {
                                          CODIFY("keyword");
                                          BEGIN(CommentDecl);
                                        }
  "IGNORE"                              {
                                          CODIFY("keyword");
                                          BEGIN(WhitespaceDecl);
                                        }
  "<"|"<."                              {
                                          yyextra->depth = 0;
                                          yyextra->code->codify(yytext);
                                          yyextra->lastContext = YY_START;
                                          BEGIN(Attribute);
                                        }
  "="                                   {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Production);
                                        }
  {IDENT}                               generateRuleLink(yyscanner,*yyextra->code,yytext); 
}

<FunctionDefinition>{
  {IDENT}                               {
                                          yyextra->code->codify(yytext);
                                        }
  "}"                                   {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Top);
                                        }
}

<GrammarDef>{
  {IDENT}                               {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Top);
                                        }
}

<Annotation>{
  {IDENT}                               {
                                          CODIFY("preprocessor");
                                          BEGIN(Top);
                                        }
}

<Attribute>{
  "<"                                   {
                                          yyextra->depth++;
                                          yyextra->code->codify(yytext);
                                        }
  ">"|".>"                              {
                                          if (yyextra->depth == 0) {
                                            BEGIN(yyextra->lastContext);
                                          } else {
                                            yyextra->depth--;
                                          }
                                          yyextra->code->codify(yytext);
                                        }
  "out"                                 CODIFY("vhdldigit");  // vhdllogic is used for the color violet
  {IDENT}/{s}(","|".>")                 { // Using look-ahead to check if a "," or ".>" are following after an identity, 
                                          // indicating a name, which doesn't require referencing  
                                          yyextra->code->codify(yytext);
                                        }
  {IDENT}/{s}(">")                      { // Using look-ahead to check if a ">" are following after an identity, 
                                          // to check whether it is the end of an attribute or not, since something like 
                                          // <out List<attribute> definition> requires "attribute" to be referenced but "definition" not
                                          if (yyextra->depth > 0) generateRuleLink(yyscanner,*yyextra->code,yytext); 
                                          else yyextra->code->codify(yytext);
                                        }
  {IDENT}                               generateRuleLink(yyscanner,*yyextra->code,yytext); 
}

<Production>{
  "<"|"<."                              {
                                          yyextra->depth = 0;
                                          yyextra->code->codify(yytext);
                                          yyextra->lastContext = YY_START;
                                          BEGIN(Attribute);
                                        }
  "ANY"|"IF"|"WEAK"|"SYNC"|"CONTEXT"    CODIFY("keyword");
  ({IDENT}\.)+({IDENT}|\*)              yyextra->code->codify(yytext);
  {IDENT}                               generateRuleLink(yyscanner,*yyextra->code,yytext); 
  "."                                   {
                                          yyextra->code->codify(yytext);
                                          BEGIN(Top);
                                        }
}

<CommentDecl>{
  "COMMENTS FROM"                       |
  "NESTED"                              |
  "TO"                                  |
  "IGNORE"                              CODIFY("keyword");
  "PRODUCTIONS"                         {
                                          CODIFY("keyword");
                                          BEGIN(Top);
                                        }
  "END"                                 {
                                          CODIFY("keyword");
                                          BEGIN(End);
                                        }
}

<WhitespaceDecl>{
  "IGNORE"                              |
  "ANY"                                 CODIFY("keyword");
  "PRODUCTIONS"                         {
                                          CODIFY("keyword");
                                          BEGIN(Top);
                                        }
  "END"                                 {
                                          CODIFY("keyword");
                                          BEGIN(End);
                                        }
}

<End>{
  {IDENT}                               yyextra->code->codify(yytext);
}



<*>{
    "//"                                {
                                          yyextra->docBlockContext = YY_START;
                                          startFontClass(yyscanner,"comment");
                                          yyextra->code->codify(yytext);
                                          BEGIN(LineComment);
                                        }
    "/*"                                {
                                          yyextra->docBlockContext = YY_START;
                                          startFontClass(yyscanner,"comment");
                                          yyextra->code->codify(yytext);
                                          BEGIN(BlockComment);
                                        }
    {CHAR}                              CODIFY("vhdllogic"); // vhdllogic is used for the color red
    {STRING}                            CODIFY("vhdllogic"); // vhdllogic is used for the color red
    "/*"[*!]/[^*/]                      {
                                          yyextra->docBlockContext = YY_START;
                                          BEGIN(SkipBlockComment);
                                        }
    "//"[/!]                            {
                                          yyextra->docBlockContext = YY_START;
                                          BEGIN(SkipLineComment);
                                        }
    {WS}                                codifyLines(yyscanner,yytext);
    <<EOF>>                             yyterminate();
}


 /* ---- Remains catcher ------ */
<*>.                                    yyextra->code->codify(yytext);
%%

static yy_size_t yyread(yyscan_t yyscanner,char *buf,yy_size_t max_size)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  yy_size_t inputPosition = yyextra->inputPosition;
  const char *s = yyextra->inputString + inputPosition;
  yy_size_t c=0;
  while( c < max_size && *s )
  {
    *buf++ = *s++;
    c++;
  }
  yyextra->inputPosition += c;
  return c;
}

static void setCurrentDoc(yyscan_t yyscanner,const QCString &anchor)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  if (Doxygen::searchIndex.enabled())
  {
    if (yyextra->searchCtx)
    {
      Doxygen::searchIndex.setCurrentDoc(yyextra->searchCtx,yyextra->searchCtx->anchor(),FALSE);
    }
    else
    {
      Doxygen::searchIndex.setCurrentDoc(yyextra->sourceFileDef,anchor,TRUE);
    }
  }
}

/*! start a new line of code, inserting a line number if yyextra->sourceFileDef
 * is TRUE. If a definition starts at the current line, then the line
 * number is linked to the documentation of that definition.
 */
static void startCodeLine(yyscan_t yyscanner)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  if (yyextra->sourceFileDef && yyextra->lineNumbers)
  {
    const Definition *d = yyextra->sourceFileDef->getSourceDefinition(yyextra->yyLineNr);

    if (!yyextra->includeCodeFragment && d)
    {
      yyextra->currentDefinition = d;
      yyextra->currentMemberDef = yyextra->sourceFileDef->getSourceMember(yyextra->yyLineNr);
      QCString lineAnchor;
      lineAnchor.sprintf("l%05d",yyextra->yyLineNr);
      if (yyextra->currentMemberDef)
      {
        yyextra->code->writeLineNumber(yyextra->currentMemberDef->getReference(),
                                yyextra->currentMemberDef->getOutputFileBase(),
                                yyextra->currentMemberDef->anchor(),
                                yyextra->yyLineNr,!yyextra->includeCodeFragment);
        setCurrentDoc(yyscanner,lineAnchor);
      }
      else if (d->isLinkableInProject())
      {
        yyextra->code->writeLineNumber(d->getReference(),
                                d->getOutputFileBase(),
                                QCString(),yyextra->yyLineNr,!yyextra->includeCodeFragment);
        setCurrentDoc(yyscanner,lineAnchor);
      }
    }
    else
    {
      yyextra->code->writeLineNumber(QCString(),QCString(),QCString(),yyextra->yyLineNr,
                                     !yyextra->includeCodeFragment);
    }
  }
  yyextra->code->startCodeLine(yyextra->yyLineNr);
  yyextra->insideCodeLine = true;  
  if (yyextra->currentFontClass)
  {
    yyextra->code->startFontClass(yyextra->currentFontClass);
  }
}

static void endFontClass(yyscan_t yyscanner, bool specialComment)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  if (yyextra->currentFontClass)
  {
    yyextra->code->endFontClass();
    yyextra->currentFontClass=nullptr;
  }
  if (specialComment && yyextra->insideSpecialComment)
  {
    yyextra->code->endSpecialComment();
    yyextra->insideSpecialComment = false;
  }
}

static void endCodeLine(yyscan_t yyscanner)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  endFontClass(yyscanner);
  yyextra->code->endCodeLine();
  yyextra->insideCodeLine = false;
}

static void nextCodeLine(yyscan_t yyscanner)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  const char *fc = yyextra->currentFontClass;
  if (yyextra->insideCodeLine)
  {
    endCodeLine(yyscanner);
  }
  if (yyextra->yyLineNr<yyextra->inputLines)
  {
    yyextra->currentFontClass = fc;
    startCodeLine(yyscanner);
  }
}

static void codifyLines(yyscan_t yyscanner,const QCString &text)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  if (text.isEmpty()) return;
  const char *p=text.data(),*sp=p;
  char c;
  bool done=FALSE;
  while (!done)
  {
    sp=p;
    while ((c=*p++) && c!='\n');
    if (c=='\n')
    {
      yyextra->yyLineNr++;
      size_t l = static_cast<size_t>(p-sp-1);
      yyextra->code->codify(QCString(sp,l));
      nextCodeLine(yyscanner);
    }
    else
    {
      yyextra->code->codify(sp);
      done=TRUE;
    }
  }
}

/*! writes a link to a fragment \a text that may span multiple lines, inserting
 * line numbers for each line. If \a text contains newlines, the link will be
 * split into multiple links with the same destination, one for each line.
 */
static void writeMultiLineCodeLink(yyscan_t yyscanner,OutputCodeList &ol,
                                   const Definition *d,
                                   const QCString &text)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  bool sourceTooltips = Config_getBool(SOURCE_TOOLTIPS);
  yyextra->tooltipManager.addTooltip(d);
  QCString ref  = d->getReference();
  QCString file = d->getOutputFileBase();
  QCString anchor = d->anchor();
  QCString tooltip;
  if (!sourceTooltips)
  {
    tooltip = d->briefDescriptionAsTooltip();
  }
  bool done=FALSE;
  const char *p=text.data();
  while (!done)
  {
    const char *sp=p;
    char c = 0;
    while ((c=*p++) && c!='\n') { }
    if (c=='\n')
    {
      yyextra->yyLineNr++;
      //DBG_CTX((stderr,"writeCodeLink(%s,%s,%s,%s)\n",qPrint(ref),qPrint(file),qPrint(anchor),qPrint(QCString(sp,p-sp-1))));
      ol.writeCodeLink(d->codeSymbolType(),ref,file,anchor,QCString(sp,p-sp-1),tooltip);
      nextCodeLine(yyscanner);
    }
    else
    {
      //DBG_CTX((stderr,"writeCodeLink(%s,%s,%s,%s)\n",qPrint(ref),qPrint(file),qPrint(anchor),sp));
      ol.writeCodeLink(d->codeSymbolType(),ref,file,anchor,sp,tooltip);
      done=TRUE;
    }
  }
}

static void startFontClass(yyscan_t yyscanner,const char *s,bool specialComment)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  endFontClass(yyscanner);
  if (specialComment)
  {
    yyextra->code->startSpecialComment();
    yyextra->insideSpecialComment = true;
  }
  yyextra->code->startFontClass(s);
  yyextra->currentFontClass=s;
}

/*! counts the number of lines in the input */
static int countLines(yyscan_t yyscanner)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  const char *p=yyextra->inputString;
  char c;
  int count=1;
  while ((c=*p))
  {
    p++ ;
    if (c=='\n') count++;
  }
  if (p>yyextra->inputString && *(p-1)!='\n')
  { // last line does not end with a \n, so we add an extra
    // line and explicitly terminate the line after parsing.
    count++;
    //yyextra->needsTermination=TRUE;
  }
  return count;
}

static void addToSearchIndex(yyscan_t /*yyscanner*/,const QCString &text)
{
  if (Doxygen::searchIndex.enabled())
  {
    Doxygen::searchIndex.addWord(text,FALSE);
  }
}




// TODO
static const MemberDef *resolveLinkToMemberDef(yyscan_t yyscanner,
                                               const QCString &scope,
                                               const QCString &name)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;

  GetDefInput input(scope, name, "()");
  input.currentFile = yyextra->sourceFileDef;
  input.insideCode  = true;

  GetDefResult r = getDefs(input);
  if (r.found && r.md && r.md->isLinkable())
  {
    const MemberDef *md = r.md->resolveAlias();
    // Optional: if you want to ensure it links somewhere valid:
    const Definition *d =
      (md->getOuterScope()==Doxygen::globalScope) ? md->getFileDef() : md->getOuterScope();
    if (md->getGroupDef()) d = md->getGroupDef();
    if (d && d->isLinkable()) return md;
  }
  return nullptr;
}


static const char *classForGrammarMd(const MemberDef *md) {
  if (!md) return NULL; 

  switch (md->memberType()) {
    case MemberType::GrammarProduction: return "production";  // #3D578C
    default:                            return "token";      // #E08000
  }
}


static bool getLinkInScope(yyscan_t yyscanner,
                           const QCString &c,  // scope
                           const QCString &m,  // member
                           const QCString &memberText, // exact text
                           OutputCodeList &ol,
                           const QCString &text,
                           bool varOnly
                          )
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  
  GetDefInput input(c, m, "()");
  input.currentFile = yyextra->sourceFileDef;
  input.insideCode  = TRUE;

  GetDefResult result = getDefs(input);

  if (!result.found || result.md==nullptr) return FALSE;
  if (varOnly && !result.md->isVariable()) return FALSE;
  if (!result.md->isLinkable()) return FALSE;

  const MemberDef *md = result.md->resolveAlias();

  const Definition *d = result.md->getOuterScope()==Doxygen::globalScope ?
                            result.md->resolveAlias()->getFileDef() : result.md->getOuterScope();
  if (result.md->resolveAlias()->getGroupDef()) d = result.md->resolveAlias()->getGroupDef();                 
  

  if (!d || !d->isLinkable()) return FALSE;

  if (yyextra->currentDefinition && yyextra->currentMemberDef && yyextra->collectXRefs)
  {
    fprintf(stderr, "\nReference added: from-%s to-%s\n\n", 
    yyextra->currentMemberDef->name().data(),
    md->name().data()
    );
    addDocCrossReference(yyextra->currentMemberDef, md);
  }

  const QCString linkText = !text.isEmpty() ? text : memberText;
  writeMultiLineCodeLink(yyscanner, ol, md, linkText);
  addToSearchIndex(yyscanner, linkText);
  return TRUE;
}

static bool getLink(yyscan_t yyscanner,
                    const QCString &className,
                    const QCString &memberName,
                    OutputCodeList &ol,
                    const QCString &text,
                    bool varOnly)
{
  QCString m=removeRedundantWhiteSpace(memberName);
  QCString c=className;

  return getLinkInScope(yyscanner, c, m, memberName, ol, text, varOnly);
}


static void generateGlobalLink(yyscan_t yyscanner,
                               OutputCodeList &ol,
                               const QCString &scName,
                               bool typeOnly,
                               bool varOnly)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  QCString scopeName=scName;

  if (scopeName.isEmpty()) return;

  int scopeEnd = scopeName.findRev(".");
  if (scopeEnd!=-1 && !typeOnly)
  {
    QCString scope = substitute(scopeName.left(scopeEnd),".","::");
    QCString locName = scopeName.right(scopeName.length()-scopeEnd-1);
    if (const NamespaceDef *nd = getResolvedNamespace(scope); nd && nd->isLinkable())
    {
      const MemberDef *md = nd->getMemberByName(locName);
      if (md && (!varOnly || md->isVariable()) && md->isLinkable())
      {
        writeMultiLineCodeLink(yyscanner, ol, md, scName);
        addToSearchIndex(yyscanner, scopeName);
        const Definition *d = md->getOuterScope()==Doxygen::globalScope ?
                              md->getBodyDef() : md->getOuterScope();
        if (d && d->isLinkable() && yyextra->currentMemberDef && yyextra->collectXRefs)
        {
          addDocCrossReference(yyextra->currentMemberDef, md);
        }
        return;
      }
    }
    
  }

  codifyLines(yyscanner, scName);
  addToSearchIndex(yyscanner, scopeName);
}

static void generateRuleLink(yyscan_t yyscanner,
                                OutputCodeList &ol,
                                const char *funcName)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  QCString locScope=yyextra->scope;
  QCString locFunc=removeRedundantWhiteSpace(funcName);
  int i=locFunc.findRev("::");
  
  if (i>0)
  {
    locScope=locFunc.left(i);
    locFunc=locFunc.right(locFunc.length()-i-2).stripWhiteSpace();
  }

  const MemberDef *md = resolveLinkToMemberDef(yyscanner, locScope, locFunc);
  const char *style = classForGrammarMd(md);

  if (style) ol.startFontClass(style);

  if (!getLink(yyscanner,locScope,locFunc,ol,funcName,/*varOnly=*/false))
  {
    generateGlobalLink(yyscanner,ol,funcName, /*typeOnly=*/false, /*varOnly=*/false);
  }

  if (style) ol.endFontClass();
}

// public interface -----------------------------------------------------------

struct CocoRCodeParser::Private
{
  yyscan_t yyscanner;
  cocorcodeYY_state state;
};

CocoRCodeParser::CocoRCodeParser() : p(std::make_unique<Private>()){
  cocorcodeYYlex_init_extra(&p->state, &p->yyscanner);
#ifdef FLEX_DEBUG
  cocorcodeYYset_debug(1,p->yyscanner);
#endif
  resetCodeParserState();
}

CocoRCodeParser::~CocoRCodeParser(){
  cocorcodeYYlex_destroy(p->yyscanner);
}

void CocoRCodeParser::resetCodeParserState()
{
  struct yyguts_t *yyg = (struct yyguts_t*)p->yyscanner;
  yyextra->theVarContext.clear();
  while (!yyextra->scopeNameLengthStack.empty()) yyextra->scopeNameLengthStack.pop_back();
  yyextra->codeClassMap.clear();
  yyextra->curClassBases.clear();
  yyextra->anchorCount = 0;
  yyextra->insideCodeLine = false;
}

void CocoRCodeParser::setInsideCodeLine(bool inp)
{
  struct yyguts_t *yyg = (struct yyguts_t*)p->yyscanner;
  yyextra->insideCodeLine = inp;
}

bool CocoRCodeParser::insideCodeLine() const
{
  struct yyguts_t *yyg = (struct yyguts_t*)p->yyscanner;
  return yyextra->insideCodeLine;
}

void CocoRCodeParser::parseCode(OutputCodeList &od,const QCString &scopeName,const QCString &s,
                SrcLangExt lang,bool stripCodeComments,const CodeParserOptions &options)
{
  yyscan_t yyscanner = p->yyscanner;
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  
  if (s.isEmpty()) return;

  yyextra->code = &od;
  yyextra->inputString   = s.data();
  yyextra->inputPosition = 0;
  yyextra->currentFontClass = nullptr;
  yyextra->needsTermination = false;

  yyextra->searchCtx = options.searchCtx();
  yyextra->collectXRefs = options.collectXRefs();
  yyextra->currentMemberDef=nullptr;
  yyextra->currentDefinition = options.searchCtx() ? options.searchCtx() : getResolvedNamespace(scopeName);

  yyextra->yyLineNr    = options.startLine()!=-1 ? options.startLine() : 1;
  yyextra->inputLines  = options.endLine()!=-1   ? options.endLine()+1 : yyextra->yyLineNr + countLines(yyscanner) - 1;
  

  yyextra->sourceFileDef = options.fileDef();
  yyextra->lineNumbers   = options.fileDef() && options.showLineNumbers();

  if (options.fileDef()==nullptr)
  {
    // create a dummy filedef for the example
    yyextra->exampleFileDef = createFileDef(QCString(),(!options.exampleName().isEmpty()?options.exampleName():"generated"));
    yyextra->sourceFileDef  = yyextra->exampleFileDef.get();
  }

  if (yyextra->sourceFileDef) {
    setCurrentDoc(yyscanner,"l00001");
  }

  yyextra->includeCodeFragment = options.inlineFragment();
  // Starts line 1 on the output
  startCodeLine(yyscanner);

  cocorcodeYYrestart( 0, yyscanner );
  BEGIN(Top);
  cocorcodeYYlex(yyscanner);

  if (yyextra->insideCodeLine)
  {
    endCodeLine(yyscanner);
  }
  if (yyextra->exampleFileDef)
  {
    // delete the temporary file definition used for this example
    yyextra->exampleFileDef.reset();
    yyextra->sourceFileDef=nullptr;
  }
}

//---------------------------------------------------------------------------------

#if USE_STATE2STRING
#include "cocorcode.l.h"
#endif