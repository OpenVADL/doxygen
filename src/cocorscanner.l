/*****************************************************************************
 *
 *
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
%option prefix="cocorscannerYY"
%option reentrant
%option extra-type="struct cocorscannerYY_state *"
%option noyywrap

%top{
#include <stdint.h>
}

%{
#include <algorithm>
#include <vector>
#include <utility>

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <ctype.h>
#include <regex>
//#include <qregexp.h>
//#include <qcstringlist.h>

#include "doxygen.h"
#include "config.h"
#include "cocorscanner.h"
#include "commentscan.h"
#include "entry.h"
#include "message.h"
#include "util.h"
#include "scanner.h"
#include "markdown.h"
#include "md5.h"


#define OUT fprintf

#define YY_NO_INPUT 1
#define YY_NO_UNISTD_H 1

#define USE_STATE2STRING 0

struct cocorscannerYY_state{
  OutlineParserInterface    *thisParser;
  CommentScanner            commentScanner;
  const char *              inputString = 0;
  int                       inputPosition = 0;

  int                       lastContext = 0;
  int                       lastSkipCommentContext = 0;
  int                       yyLineNr     = 1 ;
  int                       yyColNr     = 0 ;
  int                       column = 0;

  int                       lastSemanticActionContext = 0;

  int                       depth = 0;

  TextStream                docBlock;
  QCString                  docBlockName;
  bool                      docBlockInBody = false;
  bool                      docBlockAutoBrief = false;
  int                       docBlockContext  = 0;
  size_t                    fencedSize = 0;
  int                       nestedComment = false;

  QCString                  prefix = "yy";
  QCString                  currentProgram = "";

  QCString                  yyFileName;
  QCString                  grammar;

  /* ------ Argument/Attribute ------ */
  QCString                  argString = "";
  QCString                  curArgDocs;
  Argument                  curArg;
  bool                      argsSet = false;
  char                      lastCopyArgChar = '\0';

  int                       lastCommentInArgContext = 0;


  /* ------ AST Entries ------ */
  std::shared_ptr<Entry>    current;
  std::shared_ptr<Entry>    current_rule;
  std::shared_ptr<Entry>    current_root;
  std::shared_ptr<Entry>    previous;
  SrcLangExt                language;
};

#if USE_STATE2STRING
static const char *stateToString(int state);
#endif
//-----------------------------------------------------------------------------

// forward declarations for stateless functions
static inline int computeIndent(const char *s,int startIndent);

// forward declarations for stateful functions
static yy_size_t yyread(yyscan_t yyscanner, char *buf, yy_size_t max_size);
static void initEntry(yyscan_t yyscanner);
static void newEntry(yyscan_t yyscanner);
static void lineCountAndAddToProgram(yyscan_t yyscanner, bool addToProgram=FALSE);
static void startCommentBlock(yyscan_t yyscanner,bool);
static void handleCommentBlock(yyscan_t yyscanner,const QCString &doc,bool brief);
static void handleParametersCommentBlocks(yyscan_t yyscanner,ArgumentList &al);
static void initRule(yyscan_t yyscanner);
static void finalizeRule(yyscan_t yyscanner);

// Regex 
static inline bool isWs(char c);
static void removeWsBeforeChar(QCString &s, char ch);
static void removeWsAfterChar(QCString &s, char ch);
static void normalizeCommaSpace(QCString &s);
/* ----------------------------------------------------------------- */

/* Define Custom YY_INPUT. We use yyread(...) instead */
#undef  YY_INPUT
#define YY_INPUT(buf, result, max_size) result = yyread(yyscanner, buf, max_size);

%}

LETTER        [A-Z]|[a-z]|_
DIGIT         [0-9]
STRINGCHAR    [^\"\\\r\n]
CHARCHAR      [^'\\\r\n]
ESCAPE        \\["'\\abfnrtv0]
UNICODE       \\u[0-9a-fA-F]{4}
WS            [ \t\r\n]

s             {WS}*

STRING        \"({STRINGCHAR}|{ESCAPE}|{UNICODE})*\" 
CHAR          \'({CHARCHAR}|{ESCAPE}|{UNICODE})\'
IDENT         {LETTER}({LETTER}|{DIGIT}|_)*
NUMBER        {DIGIT}+
PACKAGE       \$package\s*=\s*{IDENT}(\.{IDENT})*

IMPORT_PATH   ({IDENT}\.)+({IDENT}|\*);

JAVA_IMPORT   "import"[ \t]+{QUALIFIED};
CSHARP_IMPORT "using"[ \t]+{QUALIFIED};
CPP_IMPORT    "#include"[ \t]+("<"{QUALIFIED}">"|\"[^\"]+\")

BASICSET      {STRING}|{IDENT}|{CHAR}[ \t]*(\.\.[ \t]*{CHAR})?|ANY

SYMBOL        {IDENT}|{STRING}|{CHAR}

PARAMETERS    {IDENT}?(,{IDENT})*
GENERIC       "<"({IDENT}(\.{IDENT})*|,|\s|[<>])*">"
QUALIFIED     {IDENT}(\.{IDENT})*
TYPE          ({GENERIC}\s*)?{QUALIFIED}({GENERIC})*("[]"*)*

FUNCTION      {TYPE}[ \t]+{IDENT}[ \t]*"("{PARAMETERS}")"
VARIABLE      {TYPE}[ \t]+{IDENT}
ANNOTATION    @{IDENT}

CMD           ("\\"|"@")
BN            [ \t\n\r]
B             [ \t]
PRE           [pP][rR][eE]
CODE          [cC][oO][dD][eE]

ID            "^"?[a-zA-Z_][a-zA-Z_0-9]*


%x SemanticAction
%x VariableDefinition
%x FunctionDefinition

%x Initial
%x Imports
%x ImportDef
%x JavaImport
%x CSharpImport
%x CPlusPlusImport

%x CompilerName
%x Global
%x GlobalSignature
%x Generic
%x FunctionDecl
%x VariableDecl
%x Characters
%x CharSetDecl
%x CharSet
%x Tokens
%x TokenDecl
%x Pragmas
%x CommentDecl
%x WhitespaceDecl
%x ParserSpec
%x Production
%x IfStatement
%x Attribute
%x End


%x SkipLineComment
%x SkipBlockComment

%x DocLine
%x DocBlock
%x DocCopyBlock

%x CopyArgComment
%x CopyArgCommentLine

%%
 /* Semantic Action Handling - Ignore */

<SemanticAction>{
  ".)"                                  {
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(yyextra->lastSemanticActionContext);
                                        }
  .                                     {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
}

 /* CoCo/R Grammar */


    /* Section Transitions - For better readability */
<Global>{
  "CHARACTERS"                          { 
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(Characters);
                                        }
  "TOKENS"                              { 
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(Tokens);
                                        }
  "PRAGMAS"                             { 
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(Pragmas);
                                        }
  "PRODUCTIONS"                         {
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(ParserSpec);
                                        }
  "COMMENTS FROM"                       {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Comment_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(CommentDecl);
                                        }
  "IGNORE"                              {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Whitespace_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(WhitespaceDecl);
                                        }
  "END"                                 {
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(End);
                                        }
}

<Characters>{
  "TOKENS"                              { 
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(Tokens);
                                        }
  "PRAGMAS"                             { 
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          BEGIN(Pragmas);
                                        }
  "PRODUCTIONS"                         {
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          BEGIN(ParserSpec);
                                        }
  "COMMENTS FROM"                       {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Comment_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(CommentDecl);
                                        }
  "IGNORE"                              {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Whitespace_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(WhitespaceDecl);
                                        }
  "END"                                 {
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          BEGIN(End);
                                        }  
}

<Tokens>{
  "PRAGMAS"                             { 
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(Pragmas);
                                        }
  "PRODUCTIONS"                         {
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(ParserSpec);
                                        } 
  "COMMENTS FROM"                       {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Comment_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(CommentDecl);
                                        }
  "IGNORE"                              {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Whitespace_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(WhitespaceDecl);
                                        }
  "END"                                 {
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          BEGIN(End);
                                        }
}

<Pragmas>{
  "COMMENTS FROM"                       {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Comment_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(CommentDecl);
                                        }
  "IGNORE"                              {
                                          initRule(yyscanner);
                                          yyextra->current->name                = "Whitespace_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(WhitespaceDecl);
                                        }
  "PRODUCTIONS"                         {
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(ParserSpec);
                                        }
  "END"                                 {
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          BEGIN(End);
                                        }
}

<CommentDecl>{
  "COMMENTS FROM"                       {
                                          finalizeRule(yyscanner);

                                          initRule(yyscanner);
                                          yyextra->current->name                = "Comment_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "IGNORE"                              {
                                          finalizeRule(yyscanner);

                                          initRule(yyscanner);
                                          yyextra->current->name                = "Whitespace_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                          BEGIN(WhitespaceDecl);
                                        }
  "PRODUCTIONS"                         {
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          finalizeRule(yyscanner);

                                          BEGIN(ParserSpec);
                                        }
  "END"                                 {
                                          lineCountAndAddToProgram(yyscanner);

                                          finalizeRule(yyscanner);
                                          
                                          BEGIN(End);
                                        }
}

<WhitespaceDecl>{
  "IGNORE"                              {
                                          finalizeRule(yyscanner);

                                          initRule(yyscanner);
                                          yyextra->current->name                = "Whitespace_Declaration";
                                          yyextra->current->section             = EntryType::makeDeclaration();
                                          yyextra->currentProgram               = "";

                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "PRODUCTIONS"                         {
                                          lineCountAndAddToProgram(yyscanner);

                                          finalizeRule(yyscanner);

                                          BEGIN(ParserSpec);
                                        }
  "END"                                 {
                                          lineCountAndAddToProgram(yyscanner);

                                          finalizeRule(yyscanner);
                                          
                                          BEGIN(End);
                                        }
}

<ParserSpec>{
  "END"                                 {
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          BEGIN(End);
                                        }
}


    /* ------ Start of special doxygen comments ------ */


<*>"/"("*"("!"|"*"+)|"/"[/!]) { 
                                          yyextra->docBlockContext = YY_START;
                                          yyextra->docBlock.str(std::string());
                                          yyextra->docBlockInBody = (YY_START == CharSetDecl ||
                                                                     YY_START == TokenDecl   ||
                                                                     YY_START == Production);
                                          yyextra->docBlockAutoBrief = ( yytext[yyleng-2]=='*' && Config_getBool(JAVADOC_AUTOBRIEF) ) ||
                                                                       ( yytext[yyleng-2]=='!' && Config_getBool(QT_AUTOBRIEF) );
                                          startCommentBlock(yyscanner, FALSE);

                                          QCString text = yytext;
                                          if (text.find("//") != -1) {
                                              BEGIN(DocLine);
                                          } else {
                                              lineCountAndAddToProgram(yyscanner);
                                              BEGIN(DocBlock);
                                          }
}

<Global>{
  ("/*!"|"/**"|"//!"|"///")"<"            {
                                            yyextra->docBlockContext   = YY_START;
                                            yyextra->docBlockInBody    = true;
                                            yyextra->docBlockAutoBrief = ( yytext[yyleng-2]=='*' && Config_getBool(JAVADOC_AUTOBRIEF) ) ||
                                                                         ( yytext[yyleng-2]=='!' && Config_getBool(QT_AUTOBRIEF) );
                                            QCString indent;
                                            indent.fill(' ', computeIndent(yytext, yyextra->column));
                                            yyextra->docBlock.str(std::string());
                                            yyextra->docBlock << indent;

                                            if (yytext[yyleng-3] == '/') { 
                                                startCommentBlock(yyscanner, TRUE);
                                                BEGIN(DocLine);
                                            } else {
                                                lineCountAndAddToProgram(yyscanner);
                                                startCommentBlock(yyscanner, FALSE);
                                                BEGIN(DocBlock);
                                            }
                                          }
} 


<Characters,Tokens,Pragmas,ParserSpec>{
  ("/*!"|"/**"|"//!"|"///")"<"?         {
                                          yyextra->docBlockContext   = YY_START;
                                          yyextra->docBlockInBody    = FALSE;       // not inside rule body yet
                                          yyextra->docBlockAutoBrief = ( yytext[yyleng-2]=='*' && Config_getBool(JAVADOC_AUTOBRIEF) ) ||
                                                                       ( yytext[yyleng-2]=='!' && Config_getBool(QT_AUTOBRIEF) );
                                          QCString indent;
                                          indent.fill(' ', computeIndent(yytext, yyextra->column));

                                          yyextra->docBlock.str(std::string());
                                          yyextra->docBlock << indent;

                                          if (yytext[yyleng-3] == '/') { 
                                              startCommentBlock(yyscanner, TRUE);
                                              BEGIN(DocLine);
                                          } else {
                                              lineCountAndAddToProgram(yyscanner);
                                              startCommentBlock(yyscanner, FALSE);
                                              BEGIN(DocBlock);
                                          }
                                        }
}

    /* Main Grammar Part */

<Initial>{
  {PACKAGE}                             {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  "import"                              {
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(JavaImport);
                                        }
  "using"                               {
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(CSharpImport);
                                        }
  "#include"                            {
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(CPlusPlusImport);
                                        }
  "COMPILER"                            { 
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(CompilerName); 
                                        }
}


<JavaImport>{
 {WS}+                                  {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  \.|\*                                 {
                                          lineCountAndAddToProgram(yyscanner);
                                        }      
  "static"                              { 
                                          lineCountAndAddToProgram(yyscanner);
                                        } 
  {IDENT}                               {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  ";"                                   {
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(Initial);
                                        }
}

<CSharpImport>{
 {WS}+                                  {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  \.|@|_                                {
                                          lineCountAndAddToProgram(yyscanner);
                                        } 
  {IDENT}                               {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  ";"                                   {
                                          lineCountAndAddToProgram(yyscanner);
                                          
                                          BEGIN(Initial);
                                        }
}

<CPlusPlusImport>{
  {WS}+                                 { 
                                          lineCountAndAddToProgram(yyscanner); 
                                        }
  "<"[^>]+">"                           {
                                          lineCountAndAddToProgram(yyscanner);

                                          BEGIN(Initial);
                                        }
  "\""[^"]+"\""                         {
                                          lineCountAndAddToProgram(yyscanner);


                                          BEGIN(Initial);
                                        }

  \.                                    { 
                                          lineCountAndAddToProgram(yyscanner); 
                                        }
}

<CompilerName>{
  {IDENT}                               {
                                          initRule(yyscanner);
                                          yyextra->current->section             = EntryType::makeFileDoc();
                                          yyextra->current->name                = yytext;
                                          std::shared_ptr<Entry> tmp            = yyextra->current;
                                          yyextra->current_root->moveToSubEntryAndRefresh(yyextra->current);
                                          yyextra->current_root = tmp;
                                          initEntry(yyscanner);

                                          yyextra->grammar = yytext;

                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(Global);
                                        }
}

<Global>{
  {WS}+                                 lineCountAndAddToProgram(yyscanner, TRUE);
  "IGNORECASE"                          {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  "{"                                   { 
                                          // Disables Function generation
                                          //initRule(yyscanner);
                                          //yyextra->current->name = "CONSTRUCTOR";
                                          //yyextra->current->section = Entry::FUNCTION_SEC;

                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(FunctionDecl);    
                                        }
  {QUALIFIED}                           { 
                                          // Disables Function generation
                                          // initRule(yyscanner);
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(GlobalSignature);    
                                        }
  {ANNOTATION}                          { 
                                          lineCountAndAddToProgram(yyscanner);
                                        }
}

<GlobalSignature>{
  {WS}+|"("|")"                         lineCountAndAddToProgram(yyscanner);
  "<"                                   { 
                                          lineCountAndAddToProgram(yyscanner);  

                                          yyextra->depth = 0;
                                          BEGIN(Generic);
                                        }
  "="                                   {
                                          lineCountAndAddToProgram(yyscanner);
                                          // yyextra->current->section = Entry::VARIABLE_SEC;
                                          BEGIN(VariableDecl);
                                        }
  "{"                                   {
                                          lineCountAndAddToProgram(yyscanner);
                                          // yyextra->current->section = Entry::FUNCTION_SEC;
                                          BEGIN(FunctionDecl);
                                        }
  {IDENT}/{s}(\(|\=|\;)                 {
                                          lineCountAndAddToProgram(yyscanner);

                                          // yyextra->current->name = yytext;
                                        }
  {IDENT}                               {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
}

<Generic>{
  {WS}+                                 lineCountAndAddToProgram(yyscanner);
  {IDENT}                               {
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  "<"                                   {
                                          lineCountAndAddToProgram(yyscanner);
                                          yyextra->depth++;
                                        }
  ">"                                   {
                                          lineCountAndAddToProgram(yyscanner);
                                          if (yyextra->depth == 0) {
                                            BEGIN(GlobalSignature);
                                          } else {
                                            yyextra->depth--;
                                          }
                                        }
}

<FunctionDecl>{
  {WS}+                                 |
  "{"                                   |
  [^}]                                  lineCountAndAddToProgram(yyscanner);
  "}"                                   {
                                          lineCountAndAddToProgram(yyscanner);

                                          finalizeRule(yyscanner);

                                          BEGIN(Global);
                                        }
}

<VariableDecl>{
  {WS}+                                 |
  "="                                   |
  [^;]                                  lineCountAndAddToProgram(yyscanner);
}

<VariableDecl,GlobalSignature>{
    ";"                                   {
                                          lineCountAndAddToProgram(yyscanner);

                                          finalizeRule(yyscanner);

                                          BEGIN(Global);
                                        }
}

<Characters>{
  {IDENT}                               { 
                                          initRule(yyscanner);
                                          yyextra->current->section             = EntryType::makeGrammarCharacter();
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(CharSetDecl);
                                        }    
}

<CharSetDecl>{
  {WS}+                                 lineCountAndAddToProgram(yyscanner, TRUE);
  {BASICSET}                            {
                                          if (yyextra->current->bodyLine == -1) {
                                            yyextra->current->bodyLine = yyextra->yyLineNr;
                                            yyextra->current->bodyColumn = yyextra->yyColNr;
                                          }

                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "="                                   lineCountAndAddToProgram(yyscanner, TRUE);
  [+-]                                  {
                                          if (yyextra->current->bodyLine == -1) {
                                            yyextra->current->bodyLine = yyextra->yyLineNr;
                                            yyextra->current->bodyColumn = yyextra->yyColNr;
                                          }

                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "."                                   {
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          finalizeRule(yyscanner);

                                          BEGIN(Characters);
                                        }             
}

<Tokens>{
  {SYMBOL}                              {
                                          initRule(yyscanner);

                                          yyextra->current->section = EntryType::makeGrammarToken();

                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          yyextra->lastContext = YY_START;
                                          BEGIN(TokenDecl);
                                        }
}

<TokenDecl>{
  {WS}+                                 lineCountAndAddToProgram(yyscanner, TRUE);
  "CONTEXT"                             {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  {SYMBOL}                              {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "("|")"|"{"|"}"|"["|"]"|"|"           {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "="                                   {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "."                                   {
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          finalizeRule(yyscanner);

                                          BEGIN(yyextra->lastContext);
                                        }
}

<Pragmas>{
  "(."                                  {
                                          yyextra->lastSemanticActionContext = YY_START;
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(SemanticAction);
                                        }
  {SYMBOL}                              {
                                          initRule(yyscanner);

                                          yyextra->current->section = EntryType::makeGrammarPragma();

                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          yyextra->lastContext = YY_START;
                                          BEGIN(TokenDecl);
                                        }  
}

<CommentDecl>{
  {WS}+                                 {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  {CHAR}                                {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  {STRING}                              { // Requires to check length of string between and 2
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "eol"|"TO"|"NESTED"                   { // We don't need to check the syntax, we only need the symbols
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
}

<WhitespaceDecl>{
  {WS}+                                 {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  {BASICSET}                            {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  [+-]                                  {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
}

<ParserSpec>{
  {IDENT}                               {

                                          initRule(yyscanner);
                                          yyextra->current->section = EntryType::makeGrammarProduction();;
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          BEGIN(Production);
                                        }
  
}

<Production>{
  {WS}+                                 lineCountAndAddToProgram(yyscanner, TRUE);
  "IF"({WS}+)"("                        {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                          yyextra->depth = 0;
                                          BEGIN(IfStatement);
                                        } 
  "<"|"<."                              {
                                          yytext = "<";

                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          yyextra->depth = 0;
                                          yyextra->lastContext = YY_START;
                                          BEGIN(Attribute);
                                        }
  "(."                                  {
                                          yyextra->lastSemanticActionContext = YY_START;
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(SemanticAction);
                                        }
  [=(){}|/]|"["|"]"                     {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "ANY"                                 {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "WEAK"|"SYNC"                         { 
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  {QUALIFIED}{IDENT}|{STRING}|{CHAR}    { 
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
  "."                                   {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                          finalizeRule(yyscanner);
                                          yyextra->argsSet = false;

                                          BEGIN(ParserSpec);
                                        }
}

<IfStatement>{
  {WS}+                                 lineCountAndAddToProgram(yyscanner, TRUE);
  "("                                   {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                          yyextra->depth++;
                                        }
  ")"                                   {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                          if (yyextra->depth == 0) {
                                            BEGIN(Production);
                                          } else {
                                            yyextra->depth--;
                                          }
                                        }
  .                                     {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }

}

<Attribute>{
  {WS}+                                 {
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          yyextra->argString += yytext;
                                        }
  "<"                                   {
                                          yyextra->argString += yytext;

                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          yyextra->depth++;
                                        }
  (([>,]|".>"){s})?"/"("*"[*!]|"/"[/!])"<"  {
                                              if (yytext == ".>") {
                                                yytext = ">";
                                              }
                                              if (yyextra->depth == 0) {
                                                yyextra->lastCopyArgChar = 0;
                                                if (yytext[0] != '/') {
                                                    yyextra->lastCopyArgChar = *yytext;
                                                }
                                                yyextra->lastCommentInArgContext = YY_START;
					                                      QCString text = yytext;

                                                if (text.find("//") != -1) {
                                                    BEGIN(CopyArgCommentLine);
                                                } else {
                                                    BEGIN(CopyArgComment);
                                                }
                                              }
                                              lineCountAndAddToProgram(yyscanner, TRUE);
                                            }
  ">"|".>"                              {
                                          if (yyextra->depth == 0) {
                                            yytext = ">";
                                            if (!yyextra->argsSet) {
                                              Argument a;
                                              a.name = yyextra->argString;
                                              a.type = "";
                                              yyextra->argString = "";

                                              a.docs = yyextra->curArgDocs;
                                              yyextra->curArgDocs = "";
                                              yyextra->current->argList.push_back(a);

                                              handleParametersCommentBlocks(yyscanner, yyextra->current->argList);

                                              yyextra->current->args = argListToString(yyextra->current->argList);

                                              yyextra->current->argList.clear();
                                              yyextra->argsSet = true;
                                            } else {
                                              yyextra->argString = "";
                                              yyextra->curArgDocs = "";
                                            }
                                            
                                            BEGIN(yyextra->lastContext);
                                          } else {
                                            yyextra->depth--;
                                            yyextra->argString += yytext;
                                          }
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                          removeWsBeforeChar(yyextra->currentProgram, '>');
                                          removeWsAfterChar(yyextra->currentProgram, '<');
                                        }
  {IDENT}                               {
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                          normalizeCommaSpace(yyextra->currentProgram);
                                          yyextra->argString += yytext;
                                        }
  {NUMBER}                              { 
                                          yyextra->argString += yytext;
                                          
                                          lineCountAndAddToProgram(yyscanner, TRUE); 
                                        }
  [*.+/\-]                              { 
                                          yyextra->argString += yytext;
                                          lineCountAndAddToProgram(yyscanner, TRUE); 
                                        }
  ","/{s}[^,< \t\r\n]                   { // Match a comma, but only if it is followed by optional whitespace and then a non-,< character
                                          // Doesn't consume the text after ",", since the "/" indicates a lookahead only
                                          lineCountAndAddToProgram(yyscanner, TRUE);

                                          if (!yyextra->argsSet) {
                                            Argument a;
                                            a.name = yyextra->argString;
                                            a.type = "";
                                            yyextra->argString = "";

                                            a.docs = yyextra->curArgDocs;
                                            yyextra->curArgDocs = "";
                                            yyextra->current->argList.push_back(a);
                                          }
                                        }
  ","                                   {
                                          lineCountAndAddToProgram(yyscanner, TRUE); 
                                        }
}

<End>{
  [ \t]+                                lineCountAndAddToProgram(yyscanner); // skip whitespace
  "END"                                 lineCountAndAddToProgram(yyscanner);
  {IDENT}                               ;
  "."                                   lineCountAndAddToProgram(yyscanner);
}

 /* ---- Argument comments ------ */

<CopyArgCommentLine>{
  [^\n]+			                          {
  					                              yyextra->curArgDocs+=yytext;
                                          lineCountAndAddToProgram(yyscanner);
  					                            }
  \n				                            {
                                          lineCountAndAddToProgram(yyscanner);
    					                            if (yyextra->lastCopyArgChar != 0) {
					                                    unput(yyextra->lastCopyArgChar);
                                              yyextra->yyColNr--;
                                          }

					                                BEGIN(yyextra->lastCommentInArgContext);
  					                            }
}

<CopyArgComment>{
  \n{s}"*"+/[^/]                        {
                                          yyextra->curArgDocs += *yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
  [^\*\n]+			                         {
  					                              yyextra->curArgDocs += yytext;
                                          lineCountAndAddToProgram(yyscanner);
  					                            }
  "*/"                                  {
                                          lineCountAndAddToProgram(yyscanner);
    					                            if (yyextra->lastCopyArgChar!=0) {
					                                    unput(yyextra->lastCopyArgChar);
                                              yyextra->yyColNr--;
                                          }
  					                              BEGIN(yyextra->lastCommentInArgContext); 
					                              }
  \n			                              {
  					                              yyextra->curArgDocs += *yytext;
                                          lineCountAndAddToProgram(yyscanner);
  					                            }
  .				                              {
  					                              yyextra->curArgDocs += *yytext;
                                          lineCountAndAddToProgram(yyscanner);
  					                            }
}

  /* ---- Single line comments ------ */
<DocLine>[^\n]*"\n"[ \t]*"//"[/!][<]?   { // continuation of multiline C++-style comment
                                           yyextra->docBlock << yytext;
                                           int markerLen = yytext[yyleng-1]=='<' ? 4 : 3;
                                           // TODO CORRECT?
                                           yyextra->docBlock << std::string(yytext).substr(0,yyleng-markerLen);
                                           lineCountAndAddToProgram(yyscanner);
                                        }
<DocLine>{B}*"///"[/]+{B}*/"\n"         { // ignore marker line (see bug700345)
                                          handleCommentBlock(yyscanner,yyextra->docBlock.str(),yyextra->current->brief.isEmpty());
                                          BEGIN( yyextra->docBlockContext );
                                        }
<DocLine>[^\n]*/"\n"{B}*"//"[!/]{B}*{CMD}"}"    { // next line is an end group marker, see bug 752712
                                          yyextra->docBlock << yytext;
                                          handleCommentBlock(yyscanner,yyextra->docBlock.str(),yyextra->current->brief.isEmpty());
                                          BEGIN( yyextra->docBlockContext );
                                        }
<DocLine>[^\n]*/"\n"                    { // whole line
                                          yyextra->docBlock << yytext;
                                          handleCommentBlock(yyscanner,yyextra->docBlock.str(),yyextra->current->brief.isEmpty());
                                          BEGIN( yyextra->docBlockContext );
                                        }

 /* ---- Comments blocks ------ */

<DocBlock>"*"*"*/"                      { // end of comment block
                                          handleCommentBlock(yyscanner,yyextra->docBlock.str(),FALSE);
                                          BEGIN(yyextra->docBlockContext);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>^{B}*"*"+/[^/]                {
                                          QCString indent;
                                          indent.fill(' ',computeIndent(yytext,yyextra->column));
                                          yyextra->docBlock << indent;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>^{B}*("//")?{B}*"*"+/[^//a-z_A-Z0-9*] { // start of a comment line
                                          QCString indent;
                                          indent.fill(' ',computeIndent(yytext,yyextra->column));
                                          yyextra->docBlock << indent;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>^{B}*("//"){B}*               { // strip embedded C++ comments if at the start of a line
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>"//"                          { // slashes in the middle of a comment block
                                          yyextra->docBlock << yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>"/*"                          { // start of a new comment in the
                                          // middle of a comment block
                                          yyextra->docBlock << yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>({CMD}{CMD}){ID}/[^a-z_A-Z0-9] { // escaped command
                                          yyextra->docBlock << yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>{CMD}("f$"|"f["|"f{")         {
                                          yyextra->docBlock << yytext;
                                          yyextra->docBlockName=&yytext[1];
                                          if (yyextra->docBlockName.at(1)=='{')
                                          {
                                            yyextra->docBlockName.at(1)='}';
                                          }
                                          yyextra->fencedSize=0;
                                          yyextra->nestedComment=FALSE;
                                          BEGIN(DocCopyBlock);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>{B}*"<"{PRE}">"               {
                                          yyextra->docBlock << yytext;
                                          yyextra->docBlockName="<pre>";
                                          yyextra->fencedSize=0;
                                          yyextra->nestedComment=FALSE;
                                          BEGIN(DocCopyBlock);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>{CMD}("verbatim"|"latexonly"|"htmlonly"|"xmlonly"|"manonly"|"rtfonly"|"docbookonly"|"dot"|"code")/[^a-z_A-Z0-9\-]     { // verbatim command (which could contain nested comments!)
                                          yyextra->docBlock << yytext;
                                          yyextra->docBlockName=&yytext[1];
                                          yyextra->fencedSize=0;
                                          yyextra->nestedComment=FALSE;
                                          BEGIN(DocCopyBlock);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>^({B}*"*"+)?{B}{0,3}"~~~"[~]*                {
                                          QCString pat = substitute(yytext,"*"," ");
                                          yyextra->docBlock << pat;
                                          yyextra->docBlockName="~~~";
                                          yyextra->fencedSize=pat.stripWhiteSpace().length();
                                          yyextra->nestedComment=FALSE;
                                          BEGIN(DocCopyBlock);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>^({B}*"*"+)?{B}{0,3}"```"[`]*                {
                                          QCString pat = substitute(yytext,"*"," ");
                                          yyextra->docBlock << pat;
                                          yyextra->docBlockName="```";
                                          yyextra->fencedSize=pat.stripWhiteSpace().length();
                                          yyextra->nestedComment=FALSE;
                                          BEGIN(DocCopyBlock);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>[^@*~\/\\\n]+                 { // any character that isn't special
                                          yyextra->docBlock << yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>\n                            { // newline
                                          yyextra->docBlock << *yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocBlock>.                             { // command block
                                          yyextra->docBlock << *yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }

 /* ---- Copy verbatim sections ------ */

<DocCopyBlock>"</"{PRE}">"              { // end of a <pre> block
                                          yyextra->docBlock << yytext;
                                          if (yyextra->docBlockName=="<pre>")
                                          {
                                            BEGIN(DocBlock);
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>"</"{CODE}">"             { // end of a <code> block
                                          yyextra->docBlock << yytext;
                                          if (yyextra->docBlockName=="<code>")
                                          {
                                            BEGIN(DocBlock);
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>[\\@]("f$"|"f]"|"f}")     {
                                          yyextra->docBlock << yytext;
                                          BEGIN(DocBlock);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>[\\@]("endverbatim"|"endlatexonly"|"endhtmlonly"|"endxmlonly"|"enddocbookonly"|"endmanonly"|"endrtfonly"|"enddot"|"endcode")/[^a-z_A-Z0-9] { // end of verbatim block
                                          yyextra->docBlock << yytext;
                                          if (&yytext[4]==yyextra->docBlockName)
                                          {
                                            BEGIN(DocBlock);
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>^{B}*"*"+/{BN}+           { // start of a comment line
                                          if (yyextra->docBlockName=="verbatim")
                                          {
                                            REJECT;
                                          }
                                          else if (yyextra->docBlockName=="code")
                                          {
                                            REJECT;
                                          }
                                          else
                                          {
                                            QCString indent;
                                            indent.fill(' ',computeIndent(yytext,0));
                                            yyextra->docBlock << indent;
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>^{B}*"*"+/{B}+"*"{BN}*    { // start of a comment line with two *'s
                                          if (yyextra->docBlockName=="code")
                                          {
                                            QCString indent;
                                            indent.fill(' ',computeIndent(yytext,0));
                                            yyextra->docBlock << indent;
                                          }
                                          else
                                          {
                                            REJECT;
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>^{B}*"*"+/({ID}|"(")      { // Assume *var or *(... is part of source code (see bug723516)
                                          if (yyextra->docBlockName=="code")
                                          {
                                            QCString indent;
                                            indent.fill(' ',computeIndent(yytext,-1));
                                            yyextra->docBlock << indent+"*";
                                          }
                                          else
                                          {
                                            REJECT;
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>^{B}*"*"+/{BN}*           { // start of a comment line with one *
                                          if (yyextra->docBlockName=="code")
                                          {
                                            QCString indent;
                                            if (yyextra->nestedComment) // keep * it is part of the code
                                            {
                                              indent.fill(' ',computeIndent(yytext,-1));
                                              yyextra->docBlock << indent+"*";
                                            }
                                            else // remove * it is part of the comment block
                                            {
                                              indent.fill(' ',computeIndent(yytext,0));
                                              yyextra->docBlock << indent;
                                            }
                                          }
                                          else
                                          {
                                            REJECT;
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>^({B}*"*"+)?{B}{0,3}"~~~"[~]* {
                                          QCString pat = substitute(yytext,"*"," ");
                                          yyextra->docBlock << pat;
                                          if (yyextra->fencedSize==pat.stripWhiteSpace().length())
                                          {
                                            BEGIN(DocBlock);
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>^({B}*"*"+)?{B}{0,3}"```"[`]*                 {
                                          QCString pat = substitute(yytext,"*"," ");
                                          yyextra->docBlock << pat;
                                          if (yyextra->fencedSize==pat.stripWhiteSpace().length())
                                          {
                                            BEGIN(DocBlock);
                                          }
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>[^\<@/*\]~\$\\\n]+        { // any character that is not special
                                          yyextra->docBlock << yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>"/*"|"*/"|"//"            {
                                          if (yytext[1]=='*')
                                          {
                                            yyextra->nestedComment=TRUE;
                                          }
                                          else if (yytext[0]=='*')
                                          {
                                            yyextra->nestedComment=FALSE;
                                          }
                                          yyextra->docBlock << yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>\n                        { // newline
                                          yyextra->docBlock << *yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }
<DocCopyBlock>.                         { // any other character
                                          yyextra->docBlock << *yytext;
                                          lineCountAndAddToProgram(yyscanner);
                                        }

 /* ---- Start of normal comments ------ */
<*>{
    "/*"                                {
                                          //OUT(stderr,"[cocor] Found Block Comment: %s\n", yytext);
                                          yyextra->lastSkipCommentContext = YY_START;
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(SkipBlockComment);
                                        }
    "//"                                {
                                          //OUT(stderr,"[cocor] Found Single Line Comment: %s\n", yytext);
                                          yyextra->lastSkipCommentContext = YY_START;
                                          lineCountAndAddToProgram(yyscanner);
                                          BEGIN(SkipLineComment);
                                        }
}

<SkipLineComment>{
    "\n"                                {
                                          BEGIN(yyextra->lastSkipCommentContext);
                                          lineCountAndAddToProgram(yyscanner, TRUE);
                                        }
    [^\n]+                              lineCountAndAddToProgram(yyscanner);
}

<SkipBlockComment>{
    "*/"                                {
                                          BEGIN(yyextra->lastSkipCommentContext);
                                          lineCountAndAddToProgram(yyscanner);
                                        }
    [^*]+                               lineCountAndAddToProgram(yyscanner);
    "*"+/[^/]                           lineCountAndAddToProgram(yyscanner);
}

 /* ---- Accounting for every line break not contained in a documentation ------ */
<*>\n                                   lineCountAndAddToProgram(yyscanner);                                

%%

static yy_size_t yyread(yyscan_t yyscanner, char *buf, yy_size_t max_size){
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  yy_size_t c = 0;

  while( c < max_size && yyextra->inputString[yyextra->inputPosition] ){
    *buf = yyextra->inputString[yyextra->inputPosition++] ;
    c++; buf++;
  }

  return c;
}
//-----------------------------------------------------------------------------
// REGEX
static inline bool isWs(char c)
{
  return c==' ' || c=='\t' || c=='\n' || c=='\r';
}

static void removeWsBeforeChar(QCString &s, char ch)
{
  int i = 0;
  while (i < (int)s.length())
  {
    if (s[i] == ch)
    {
      int j = i - 1;
      while (j >= 0 && isWs(s[j])) j--;
      if (j != i - 1)
      {
        s = s.left(j + 1) + s.mid(i); // drop ws before ch
        i = j + 1;                    // continue at ch
      }
    }
    i++;
  }
}

static void removeWsAfterChar(QCString &s, char ch)
{
  int i = 0;
  while (i < (int)s.length())
  {
    if (s[i] == ch)
    {
      int j = i + 1;
      while (j < (int)s.length() && isWs(s[j])) j++;
      if (j != i + 1)
      {
        s = s.left(i + 1) + s.mid(j); // drop ws after ch
      }
    }
    i++;
  }
}

static void normalizeCommaSpace(QCString &s)
{
  int i = 0;
  while (i < (int)s.length())
  {
    if (s[i] == ',')
    {
      int j = i + 1;
      while (j < (int)s.length() && isWs(s[j])) j++;
      // keep exactly one space after comma if not end
      QCString repl = (j < (int)s.length()) ? ", " : ",";
      s = s.left(i) + repl + s.mid(j);
      i += repl.length();
      continue;
    }
    i++;
  }
}

// ---------------------------------------------------------------------------------

static void newEntry(yyscan_t yyscanner){
  struct yyguts_t *yyg                  = (struct yyguts_t*)yyscanner;
  yyextra->previous                     = yyextra->current;
  yyextra->current_root->moveToSubEntryAndRefresh(yyextra->current); // Attaches the current Entry as a sub entry under the current root
  initEntry(yyscanner);
}

static void initEntry(yyscan_t yyscanner){
  struct yyguts_t *yyg                  = (struct yyguts_t*)yyscanner;
  yyextra->current->lang                = yyextra->language;
  yyextra->current->protection          = Protection::Protected;

  yyextra->commentScanner.initGroupInfo(yyextra->current.get());
}


static void initRule(yyscan_t yyscanner) {
    struct yyguts_t *yyg                = (struct yyguts_t*)yyscanner;

    yyextra->current->fileName          = yyextra->yyFileName;
    
    yyextra->current->startLine         = yyextra->yyLineNr;
    yyextra->current->startColumn       = yyextra->yyColNr;
    yyextra->current->bodyLine          = -1;
    yyextra->current->bodyColumn        = -1;
    yyextra->current->lang              = SrcLangExt::CocoR;
    yyextra->current->name              = yytext;
    yyextra->current->type              = "";
}


static void finalizeRule(yyscan_t yyscanner) {
  struct yyguts_t *yyg                  = (struct yyguts_t*)yyscanner;

  yyextra->current->program.str(std::string());  // clear
  yyextra->current->program << yyextra->currentProgram;
  yyextra->currentProgram = "";

  newEntry(yyscanner);
}
// ---------------------------------------------------------------------------------------------

static inline int computeIndent(const char *s,int startIndent){
  int col=startIndent;
  int tabSize=Config_getInt(TAB_SIZE);
  const char *p=s;
  char c;
  while ((c=*p++)){
    if (c =='\t') col + tabSize - (col % tabSize);
    else if (c =='\n') col = 0;
    else col++;
  }
  return col;
}

static void lineCountAndAddToProgram(yyscan_t yyscanner, bool addToProgram){
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  int tabSize = Config_getInt(TAB_SIZE);
  const char *p;
  for (p = yytext ; *p ; ++p ){
    if (*p=='\n'){
      yyextra->yyLineNr++,yyextra->column=0,yyextra->yyColNr=1;
    } else if (*p=='\t'){
      yyextra->column+=tabSize - (yyextra->column%tabSize);
    } else{
      yyextra->column++,yyextra->yyColNr++;
    }
  }
  if (addToProgram) {
    yyextra->currentProgram += yytext;
  }
}

static void startCommentBlock(yyscan_t yyscanner,bool brief){
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  if (brief){
    yyextra->current->briefFile = yyextra->yyFileName;
    yyextra->current->briefLine = yyextra->yyLineNr;
  } else {
    yyextra->current->docFile = yyextra->yyFileName;
    yyextra->current->docLine = yyextra->yyLineNr;
  }
}

static void handleCommentBlock(yyscan_t yyscanner,const QCString &doc,bool brief)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  bool hideInBodyDocs = Config_getBool(HIDE_IN_BODY_DOCS);
  if (yyextra->docBlockInBody && hideInBodyDocs) return;
  int lineNr = brief ? yyextra->current->briefLine : yyextra->current->docLine;   // line of block start

  // fill in inbodyFile && inbodyLine the first time, see bug 633891
  std::shared_ptr<Entry> docEntry = yyextra->docBlockInBody && yyextra->previous ? yyextra->previous : yyextra->current;
  if (yyextra->docBlockInBody && docEntry && docEntry->inbodyLine==-1)
  {
    docEntry->inbodyFile = yyextra->yyFileName;
    docEntry->inbodyLine = lineNr;
  }

  int position=0;
  bool needsEntry=FALSE;
  GuardedSectionStack guards;
  Markdown markdown(yyextra->yyFileName,lineNr);
  QCString strippedDoc = stripIndentation(doc);
  QCString processedDoc = Config_getBool(MARKDOWN_SUPPORT) ? markdown.process(strippedDoc,lineNr) : strippedDoc;
  Protection protection = Protection::Public;
  
  while (yyextra->commentScanner.parseCommentBlock(
        yyextra->thisParser,
        yyextra->docBlockInBody && yyextra->previous ? yyextra->previous.get() : yyextra->current.get(),
        processedDoc, // text
        yyextra->yyFileName,   // file
        lineNr,       // line of block start
        yyextra->docBlockInBody ? FALSE : brief,               // isBrief
        yyextra->docBlockInBody ? FALSE : yyextra->docBlockAutoBrief,   // isJavaDocStyle
        yyextra->docBlockInBody,                               // isInBody
        protection,
        position,
        needsEntry,
        Config_getBool(MARKDOWN_SUPPORT),
        &guards
        )
     )
  {
    if (needsEntry)
    {
      QCString docFile = yyextra->current->docFile;
      newEntry(yyscanner);
      yyextra->current->docFile = docFile;
      yyextra->current->docLine = lineNr;
    }
  }
  if (needsEntry)
  {
    newEntry(yyscanner);
  }
}

static void handleParametersCommentBlocks(yyscan_t yyscanner,ArgumentList &al)
{
  struct yyguts_t *yyg = (struct yyguts_t*)yyscanner;
  for (Argument &a : al)
  {
    if (!a.docs.isEmpty())
    {
      if  (a.name.isEmpty() && a.type == "...") a.name= "...";
      int position=0;
      bool needsEntry;

      // save context
      QCString orgDoc   = yyextra->current->doc;
      QCString orgBrief = yyextra->current->brief;
      int orgDocLine    = yyextra->current->docLine;
      int orgBriefLine  = yyextra->current->briefLine;

      yyextra->current->doc.clear();
      yyextra->current->brief.clear();

      int lineNr = orgDocLine;
      GuardedSectionStack guards;
      Protection protection = Protection::Public;
      Markdown markdown(yyextra->yyFileName,lineNr);
      QCString strippedDoc = stripIndentation(a.docs);
      QCString processedDoc = Config_getBool(MARKDOWN_SUPPORT) ? markdown.process(strippedDoc,lineNr) : strippedDoc;
      while (yyextra->commentScanner.parseCommentBlock(
             yyextra->thisParser,
             yyextra->current.get(),
             processedDoc,     // text
             yyextra->yyFileName,         // file
             lineNr,
             FALSE,
             FALSE,
             FALSE,
             protection,
             position,
             needsEntry,
             Config_getBool(MARKDOWN_SUPPORT),
             &guards
            )
          )
      {
        if (needsEntry) newEntry(yyscanner);
      }
      if (needsEntry)
      {
        newEntry(yyscanner);
      }
      a.docs = yyextra->current->doc;

      // restore context
      yyextra->current->doc       = orgDoc;
      yyextra->current->brief     = orgBrief;
      yyextra->current->docLine   = orgDocLine;
      yyextra->current->briefLine = orgBriefLine;
    }
  }
}

static QCString collapseBlankLines(const QCString &in) {
  std::string s = in.str();

  static const std::regex emptyLines(R"(\n[ \t]*\n+)");
  s = std::regex_replace(s, emptyLines, "\n");

  return QCString(s.c_str());
}

// Initializes the parsing process
static void parseMain(yyscan_t yyscanner,
                      const QCString &fileName,
                      const char *fileBuf,
                      const std::shared_ptr<Entry> &rt)
{
  struct yyguts_t *yyg = (struct yyguts_t*) yyscanner;

  yyextra->inputString = fileBuf;
  yyextra->inputPosition = 0;
  yyextra->column        = 0;
  yyextra->yyLineNr      = 1;
  cocorscannerYYrestart(nullptr, yyscanner);

  yyextra->yyFileName = fileName;
  yyextra->language    = getLanguageFromFileName(yyextra->yyFileName);
  rt->lang = yyextra->language;
  msg("Parsing file %s...\n", yyextra->yyFileName.data());

  yyextra->current_root  = rt;
  yyextra->commentScanner.enterFile(yyextra->yyFileName, yyextra->yyLineNr);
  yyextra->current = std::make_shared<Entry>();

  yyextra->current->name    = yyextra->yyFileName;
  yyextra->current->section = EntryType::makeSource();
  yyextra->current_root->moveToSubEntryAndRefresh(yyextra->current);
  yyextra->current->reset();

  BEGIN(Initial);

  cocorscannerYYlex(yyscanner);

  yyextra->commentScanner.leaveFile(yyextra->yyFileName,yyextra->yyLineNr);

  if (Config_getBool(GRAMMAR_RULE_BODY)) {
    // Walk the root -> section -> rule tree explicitly
    for (auto &section : rt->children()) {
      ////OUT(stderr, "Section: %s\n", section->name.data());
      for (auto &ch : section->children()) {
        QCString prog = ch->program.str();

        prog = collapseBlankLines(prog);

        if (!prog.isEmpty())
        {
          ch->doc = "\\code{.atg}\n" + prog + "\n\\endcode\n" + ch->doc;
        }
      }
    }
  }

  rt->program.str(std::string());
}

//----------------------------------------------------------------------------

struct CocoROutlineParser::Private{
  yyscan_t yyscanner;
  cocorscannerYY_state state;
};

CocoROutlineParser::CocoROutlineParser() : p(std::make_unique<CocoROutlineParser::Private>()){
  cocorscannerYYlex_init_extra(&p->state, &p->yyscanner);
    #ifdef FLEX_DEBUG
  cocorscannerYYset_debug(1, p->yyscanner);
    #endif
}

CocoROutlineParser::~CocoROutlineParser(){
  cocorscannerYYlex_destroy(p->yyscanner);
}

bool CocoROutlineParser::needsPreprocessing(const QCString &extension) const
{
  return false;
}

void CocoROutlineParser::parseInput(const QCString &fileName,
                                const char *fileBuf,
                                const std::shared_ptr<Entry> &root,
                                ClangTUParser *clangParser)
{
  struct yyguts_t *yyg = (struct yyguts_t*) p->yyscanner;
  yyextra->thisParser = this;

  ::parseMain(p->yyscanner, fileName, fileBuf, root);
}

void CocoROutlineParser::parsePrototype(const QCString &text){}


//----------------------------------------------------------------------------

#if USE_STATE2STRING
#include "cocorscanner.l.h"
#endif