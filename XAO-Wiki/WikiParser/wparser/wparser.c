#include "wparser.h"
#include <stdio.h>
#include <string.h>
#include "s_string.h"

#define PASS2SEPLEN 10

#define MAX_LIST_PATTERN 20

#define BLOCK_TYPE_TEXT     "text"
#define BLOCK_TYPE_BLOCK    "curly"
#ifdef HEADER_IS_BLOCK
#define BLOCK_TYPE_HEADER   "header"
#endif
#define BLOCK_TYPE_LINK     "link"
#define BLOCK_TYPE_ISBN     "isbn"
#define BLOCK_TYPE_NOWIKI   "rawtext"
#ifdef COMMENT_IS_BLOCK
#define BLOCK_TYPE_COMMENT  "comment"
#endif



struct wpstate {
int paragraph_started;
int boldlevel;
int italiclevel;
char listpattern[MAX_LIST_PATTERN+1];
char separator[PASS2SEPLEN];
struct gtreftable reftable;
};

struct blinetaginfo {
char *tag;
int (*proc)(char *begin, struct wpstate *state, string &s);
};

struct inlinetaginfo {
char *tag;
int (*proc)(char *fulltag, char *arg, struct wpstate *state, string &s);
};


string line_process(char *line, struct wpstate*);


#define PAIR_OMIT       0
#define PAIR_MANDAT     1
#define PAIR_SAMELINE	2
#define BREAK_P         4	//break paragraph before this tag
#define BOL             8   //must be started at begin of line 


struct globaltaginfo {
char *starttag;
char *endtag;
int  flag;
string (*proc)(char *str, struct wpstate *state);
};

const char* tag_paragraph_start             ="<p>";
const char* tag_paragraph_stop              ="</p>\n";
#ifndef HEADER_IS_BLOCK
const char* tag_h1_start                    ="<h1>";
const char* tag_h1_stop                     ="</h1>";
const char* tag_h2_start                    ="<h2>";
const char* tag_h2_stop                     ="</h2>";
const char* tag_h3_start                    ="<h3>";
const char* tag_h3_stop                     ="</h3>";
const char* tag_h4_start                    ="<h4>";
const char* tag_h4_stop                     ="</h4>";
#endif
const char* tag_hr                          ="<hr />";
const char* tag_br                          ="<br />";
const char* tag_indent_start                ="<dl><dd>";
const char* tag_indent_stop                 ="</dd></dl>";
const char* tag_newline                     ="\n";
const char* tag_definition_start            ="<dl>";
const char* tag_definition_stop             ="</dl>";
const char* tag_definition_term_start       ="<dt>";
const char* tag_definition_term_stop        ="</dt>";
const char* tag_definition_definition_start ="<dd>";
const char* tag_definition_definition_stop  ="</dd>";
const char* tag_list_ordered_start          ="<ol>";
const char* tag_list_ordered_stop           ="</ol>\n";
const char* tag_list_unordered_start        ="<ul>";
const char* tag_list_unordered_stop         ="</ul>\n";
const char* tag_list_item_start             ="<li>";
const char* tag_list_item_stop              ="</li>";
const char* tag_nowrap_start                ="<pre>";
const char* tag_nowrap_stop                 ="\n</pre>";
const char* tag_bold_start                  ="<b>";
const char* tag_bold_stop                   ="</b>";
const char* tag_italic_start                ="<i>";
const char* tag_italic_stop                 ="</i>";


string lists_stop(struct wpstate *state)
{
int i;
string s;
s="";
if(*state->listpattern)
{
  for(i=strlen(state->listpattern);i>0;i--)
    {
      s+=tag_list_item_stop;
      if(state->listpattern[i-1]=='#')
        s+=tag_list_ordered_stop;
      else
        s+=tag_list_unordered_stop;
    }
    *state->listpattern=0;
  }
return s;
}

string bolditalic_stopall(struct wpstate *state)
{
string s;
s="";
if(state->italiclevel)
 {
    state->italiclevel=0;
    s+=tag_italic_stop;
 }
if(state->boldlevel)
 {
    state->boldlevel=0;
    s+=tag_bold_stop;
 }
return s;
}

string paragraph_start(struct wpstate *state)
{
string s;
s="";
if(!state->paragraph_started)
  {
    s+=lists_stop(state);
    state->paragraph_started=1;
    s+=tag_paragraph_start;
  }
return s;
}

string paragraph_start_if_possible(struct wpstate *state)
{
string s;
s="";
if(!*state->listpattern) s=paragraph_start(state);
return s;
}

string paragraph_stop(struct wpstate *state)
{
string s;
s="";
if(state->paragraph_started)
  {
    state->paragraph_started=0;
    s+=tag_paragraph_stop;
    s+=lists_stop(state);
  }
return s;
}



int tag_hr_process(char *str, struct wpstate *state, string &s)
{
char *cp,*cp2;
s+=paragraph_stop(state);
s+=tag_hr;
cp=str;
while(*cp=='-') cp++;
cp2=cp;
while(*cp2&&(*cp2!='\n')) cp2++;
if(*cp2=='\n') *cp2++=0;
if(*cp)	//have something in tail
 {
   // No new paragraph, like in wiki media
   s+=line_process(cp,state);
 }
return cp2-str;
}

#ifndef HEADER_IS_BLOCK
int tag_h_process(char *str, struct wpstate *state, string &s)
{
char *cp,*cp2;
char *etag=0;
int nchars=1;
cp=str;
while(cp[nchars]=='=') nchars++;
if(nchars>4) nchars=4;
cp2=cp+nchars;
while((*cp2!='\n')&&(*cp2))
 {
   if(!strncmp(cp2,"====",nchars))
   {
     while (!strncmp(cp2+1,"====",nchars)) cp2++;	//right as possible
     etag=cp2;
     break;
   }
   cp2++;
 }
if(etag&&(etag-cp>nchars)) //not ========
 {
   s+=paragraph_stop(state);
   *etag=0;
   switch(nchars)
   {
     case 1:
       s+=tag_h1_start;
       break;
     case 2:
       s+=tag_h2_start;
       break;
     case 3:
       s+=tag_h3_start;
       break;
     case 4:
       s+=tag_h4_start;
       break;
   }
   cp+=nchars;	//skip ====
   s+=line_process(cp,state);
   switch(nchars)
   {
     case 1:
       s+=tag_h1_stop;
       break;
     case 2:
       s+=tag_h2_stop;
       break;
     case 3:
       s+=tag_h3_stop;
       break;
     case 4:
       s+=tag_h4_stop;
       break;
   }
   cp2=cp=etag+nchars;	//part after enddtag
   while(*cp2&&(*cp2!='\n')) cp2++;	//find eol
   if(*cp2=='\n') *cp2++=0;
   if(*cp)	//have something in tail
   {
     s+=line_process(cp,state);
   }
   return cp2-str;
 }
return 0;
}
#endif

int tag_indent_process(char *str, struct wpstate *state, string &s)
{
char *cp,*cp2;
int nchars=1,i;
cp=str;
while(cp[nchars]==':') nchars++;
cp2=cp+nchars;
while((*cp2!='\n')&&(*cp2)) cp2++;
if(*cp2=='\n') *cp2++=0;
s+=paragraph_stop(state);
if(cp[nchars]) // have something after :::
 {
   for(i=0;i<nchars;i++)
     s+=tag_indent_start;
   s+=line_process(cp+nchars,state);
   for(i=0;i<nchars;i++)
     s+=tag_indent_stop;
 }
return cp2-str;
}

int tag_definition_process(char *str, struct wpstate *state, string &s)
{
char *cp,*cp2;
char *etag=0;
int dl_started=0;
cp=str;
cp2=cp+1;
while((*cp2!='\n')&&(*cp2))
 {
   if(*cp2==':')
   {
     etag=cp2;
     break;
   }
   cp2++;
 }
/*
States: have term, no definition	etag=0,
	no term, have definition
	have term, have definition
	no term, no definition		etag=0
*/
s+=paragraph_stop(state);
if(etag)	//have definition
 {
   *etag=0;
   cp++;		 //skip ';'
   if(etag!=cp)	//	have something between ; and : 
   {
     s+=tag_definition_start;
     dl_started=1;
     s+=tag_definition_term_start;
     s+=line_process(cp,state);
     s+=tag_definition_term_stop;
   }
   cp2=cp=etag+1;	//part after enddtag
   while(*cp2&&(*cp2!='\n')) cp2++;
   if(*cp2=='\n') *cp2++=0;
   if(*cp)	//have something in tail
   {
     if(!dl_started)
     {
       dl_started=1;
       s+=tag_definition_start;
     }
     s+=tag_definition_definition_start;
     s+=line_process(cp,state);
     s+=tag_definition_definition_stop;
   }
   if(dl_started) s+=tag_definition_stop;
   return cp2-str;
 }
else	//no definition, term only
 {
   cp++;		 //skip ';'
   cp2=cp;
   while(*cp2&&(*cp2!='\n')) cp2++;
   if(*cp2=='\n') *cp2++=0;
   if(*cp)	//have something in tail
   {
     s+=tag_definition_start;
     s+=tag_definition_term_start;
     s+=line_process(cp,state);
     s+=tag_definition_term_stop;
     s+=tag_definition_stop;
   }
   return cp2-str;
 }
return 0;
}

int tag_list_process(char *str, struct wpstate *state, string &s)
{
int prevpatlen,i,patlen=0;
char *cp,*cp2;
char listpattern[MAX_LIST_PATTERN+1];
cp=str;
while((cp[patlen]=='*')||(cp[patlen]=='#')) patlen++;
if(patlen>MAX_LIST_PATTERN) return 0;	//too long
strncpy(listpattern,str,patlen);
listpattern[patlen]=0;
prevpatlen=strlen(state->listpattern);
cp=str+patlen;
cp2=cp;
while(*cp2&&(*cp2!='\n')) cp2++;
if(*cp2=='\n') *cp2++=0;
if(!*cp) return cp2-str;	// no text, ignore
s+=paragraph_stop(state);	//it will not reset lists state! (I beleive;)
if(!strcmp(state->listpattern,listpattern))	//lists level not changed!
{
  s+=tag_list_item_stop;
  s+=tag_list_item_start;
  s+=line_process(cp,state);
}
else
{
if(prevpatlen==patlen)	//same level but dif lists
 {
   s+=tag_list_item_stop;
   if(state->listpattern[patlen-1]=='#')	//was ordered
   {
     s+=tag_list_ordered_stop;
     s+=tag_list_unordered_start;
   }
   else						//was unordered
   {
     s+=tag_list_unordered_stop;
     s+=tag_list_ordered_start;
   }
   strcpy(state->listpattern,listpattern);
   s+=tag_list_item_start;
   s+=line_process(cp,state);
 }
else
if(prevpatlen>patlen)	//close some levels
 {
   for(i=prevpatlen;i>patlen;i--)
   {
     s+=tag_list_item_stop;
     if(state->listpattern[i-1]=='#')
       s+=tag_list_ordered_stop;
     else
       s+=tag_list_unordered_stop;
   }
   strcpy(state->listpattern,listpattern);
   s+=tag_list_item_stop;
   s+=tag_list_item_start;
   s+=line_process(cp,state);
 }
else /*(patlen>prevpatlen)*/	//open some levels
 {
   for(i=prevpatlen;i<patlen;i++)
   {
     if(listpattern[i]=='#')
       s+=tag_list_ordered_start;
     else
       s+=tag_list_unordered_start;
     s+=tag_list_item_start;
   }
   strcpy(state->listpattern,listpattern);
   s+=line_process(cp,state);
 }
}
return cp2-str;
}

int tag_nowrap_process(char *str, struct wpstate *state, string &s)
{
char *cp,*cp2;
cp=str;
cp2=cp+1;
while((*cp2!='\n')&&(*cp2)) cp2++;
if(*cp2=='\n') *cp2++=0;
s+=paragraph_stop(state);
cp++;	//skip 1st ' '
if(*cp) // have something after ' '
 {
   s+=tag_nowrap_start;
   s+=line_process(cp,state);
   s+=tag_nowrap_stop;
 }
return cp2-str;
}


struct blinetaginfo blinetags[]={
{"---",	tag_hr_process},
#ifndef HEADER_IS_BLOCK
{"=",	tag_h_process},
#endif
{":",	tag_indent_process},
{";",	tag_definition_process},
{"*",	tag_list_process},
{"#",	tag_list_process},
{" ",	tag_nowrap_process},
{0,		NULL}
};




int register_globaltag(char *type, int level, char *content,
                                              struct gtreftable *reftable)
{
int num;
if(reftable->reflist_used==reftable->reflist_allocated)
{
  struct gtreflist *newlist;
  newlist=(struct gtreflist*)malloc(sizeof(struct gtreflist)*
                    (reftable->reflist_allocated+100));
  if(!newlist) return -1;
  memset(newlist,0,sizeof(struct gtreflist)*(reftable->reflist_allocated+100));
  if(reftable->reflist)
  {
    memcpy(newlist,reftable->reflist,
                     sizeof(struct gtreflist)*reftable->reflist_used);
    free(reftable->reflist);
  }
  reftable->reflist=newlist;
  reftable->reflist_allocated+=100;
}
reftable->reflist[reftable->reflist_used].type=type;
reftable->reflist[reftable->reflist_used].level=level;
reftable->reflist[reftable->reflist_used].text=strdup(content);
num=reftable->reflist_used++;
return num;
}

string globaltag_nowiki_process(char *str, struct wpstate *state)
{
string s;
s=state->separator;
s+=register_globaltag(BLOCK_TYPE_NOWIKI,0,str,&state->reftable);
s+=" ";
return s;
}
string globaltag_comment_process(char *str, struct wpstate *state)
{
string s;
s="";
#ifdef COMMENT_IS_BLOCK
s=state->separator;
s+=register_globaltag(BLOCK_TYPE_COMMENT,0,str,&state->reftable);
s+=" ";
#endif
return s;
}

int free_reftable(struct gtreftable *reftable)
{
int i;
if(!reftable->reflist) return 0;
for(i=0;i<reftable->reflist_used;i++)
  free(reftable->reflist[i].text);
reftable->reflist_used=0;
reftable->reflist_allocated=0;
free(reftable->reflist);
reftable->reflist=NULL;
return 0;
}

char *alltrim(char *str)
{
if(!str) return "";
char *cp,*cp2;
cp=str;
while(*cp==' ') cp++;
cp2=cp;
while(*cp2) cp2++;
while(*--cp2==' ') *cp2=0;
return cp;
}

string globaltag_datablock_process(char *str, struct wpstate *state)
{
char *cp;
string s;
s="";
cp=alltrim(str);
if(!*cp) return s;
s=state->separator;
s+=register_globaltag(BLOCK_TYPE_BLOCK,0,cp,&state->reftable);
s+=" ";
cp=s;
while(*cp)
{
  if(*cp=='\n') *cp=' ';
  cp++;
}
return s;
}

#ifdef HEADER_IS_BLOCK
string globaltag_hany_process(int level,char *str, struct wpstate *state)
{
char *cp;
string s;
s="";
cp=alltrim(str);
if(!*cp) return s;
s=state->separator;
s+=register_globaltag(BLOCK_TYPE_HEADER,level,cp,&state->reftable);
s+=" ";
cp=s;
while(*cp)
{
  if(*cp=='\n') *cp=' ';
  cp++;
}
return s;
}

string globaltag_h4_process(char *str, struct wpstate *state)
{
return globaltag_hany_process(4,str,state);
}
string globaltag_h3_process(char *str, struct wpstate *state)
{
return globaltag_hany_process(3,str,state);
}
string globaltag_h2_process(char *str, struct wpstate *state)
{
return globaltag_hany_process(2,str,state);
}
string globaltag_h1_process(char *str, struct wpstate *state)
{
return globaltag_hany_process(1,str,state);
}
#endif

string globaltag_link_process(char *str, struct wpstate *state)
{
char *cp;
string s;
s="";
cp=alltrim(str);
if(!*cp) return s;
s=state->separator;
s+=register_globaltag(BLOCK_TYPE_LINK,0,cp,&state->reftable);
s+=" ";
cp=s;
while(*cp)
{
  if(*cp=='\n') *cp=' ';
  cp++;
}
return s;
}


//precedence is important for similar tags!
struct globaltaginfo globaltags[]={
{"<nowiki>","</nowiki>",           PAIR_OMIT, globaltag_nowiki_process},
{"<!--",    "-->",               PAIR_MANDAT, globaltag_comment_process},
{"{{",      "}}",  PAIR_MANDAT|PAIR_SAMELINE, globaltag_datablock_process},
{"[[",      "]]",  PAIR_MANDAT|PAIR_SAMELINE, globaltag_link_process},
#ifdef HEADER_IS_BLOCK
{"====",    "====",PAIR_MANDAT|PAIR_SAMELINE|BREAK_P|BOL,globaltag_h4_process},
{"===",     "===", PAIR_MANDAT|PAIR_SAMELINE|BREAK_P|BOL,globaltag_h3_process},
{"==",      "==",  PAIR_MANDAT|PAIR_SAMELINE|BREAK_P|BOL,globaltag_h2_process},
{"=",       "=",   PAIR_MANDAT|PAIR_SAMELINE|BREAK_P|BOL,globaltag_h1_process},
#endif
{0,0,0,NULL}
};


int line_parse(char *str, string &s, struct wpstate *state)
{
char *cp,*cp2;
int processed,i;
cp=str;
processed=0;
for(i=0;blinetags[i].tag;i++)
{
    if(!strncmp(cp,blinetags[i].tag,strlen(blinetags[i].tag)))
    {
      processed=blinetags[i].proc(cp,state,s);
      break;
    }
}
if(!processed)	//was not processed. pass line to line parser
{
    cp2=cp;
    s+=paragraph_start(state);
    while(*cp2&&(*cp2!='\n')) cp2++;
    if(*cp2=='\n') *cp2++=0;
    if(*cp) s+=line_process(cp,state);
    processed=cp2-str;
}
return processed;
}

//����� ����� ���������� ����� � �������� �� ������ �� �����
int globaltag_find(char *text, int *tagidxptr,
             char **starttagptr, int *starttaglenptr,
             char **endtagptr,   int *endtaglenptr, char *linestart)
{
char *cp,*blockend,*eol;
int i,blocklen;
int tagidx=-1,starttaglen=0,endtaglen=0;
char *starttag=0,*endtag=0;
cp=blockend=text;
eol=strchr(text,'\n');
if(!eol)
 {
   eol=text;
   while(*eol) eol++;
 }
for(;*cp&&(tagidx==-1)&&(*cp!='\n');cp++)
   for(i=0;globaltags[i].starttag;i++)
   {
     if((globaltags[i].flag&BOL)&&(cp!=linestart))  continue;
     starttaglen=strlen(globaltags[i].starttag);
     endtaglen=strlen(globaltags[i].endtag);
     if(!strncasecmp(cp,globaltags[i].starttag,starttaglen))
     {
       //look for pair
       endtag=strcasestr(cp+starttaglen,globaltags[i].endtag);
       if(!endtag&&(globaltags[i].flag&PAIR_MANDAT)) continue;
       if((endtag>eol)&&(globaltags[i].flag&PAIR_SAMELINE)) continue;
       if(endtag==cp+starttaglen) continue; // '==' case
       tagidx=i;
       starttag=cp;
       break;
     }
   }
if(starttag)
  {
    if(!endtag)
    {
      endtag=starttag+starttaglen;
      while(*endtag) endtag++;		//move to EOT
      endtaglen=0;
      blockend=endtag;
    }
    else
      blockend=endtag+endtaglen;
    blocklen=blockend-starttag;
  }
else blocklen=0;
if(tagidxptr) *tagidxptr=tagidx;
if(starttagptr) *starttagptr=starttag;
if(endtagptr) *endtagptr=endtag;
if(starttaglenptr) *starttaglenptr=starttaglen;
if(endtaglenptr) *endtaglenptr=endtaglen;
return blocklen;
}



string do_italic_stop(struct wpstate *state)
{
string s;
s="";
if(!state->italiclevel) return s;
state->italiclevel--;
if(!state->italiclevel) s+=tag_italic_stop;
return s;
}
string do_bold_stop(struct wpstate *state)
{
string s;
s="";
if(!state->boldlevel) return s;
state->boldlevel--;
if(!state->boldlevel) s+=tag_bold_stop;
return s;
}
string do_italic_start(struct wpstate *state)
{
string s;
s="";
if(!state->italiclevel) s+=tag_italic_start;
state->italiclevel++;
return s;
}
string do_bold_start(struct wpstate *state)
{
string s;
s="";
if(!state->boldlevel) s+=tag_bold_start;
state->boldlevel++;
return s;
}



#define BI_ORD_BI	0
#define	BI_ORD_IB	1
/*
'''''	'''''	=>	<b><i>  </i></b>	=> BI_ORD_BI
'''''	''' ''	=>	<i><b>  </b></i>	=> BI_ORD_IB
'''''	'' '''	=>	<b><i>  </i></b>	=> BI_ORD_BI
*/

int bolditaliconoff_process(char *tag, char *str, struct wpstate *state,
          string &s)
{
int order=BI_ORD_BI;
char *offptr;
//take distances to nearest closer
offptr=strstr(str,"''");
if(offptr&&(offptr[2]=='\'')&&(offptr[3]!='\'')) order=BI_ORD_IB;
/*
  possible prev state		action
1  bi (no b, no i)		turn on b,i in guessed order
2  B i (was b, no i)		turn off b, turn on i
3  b I (no b, was I)		turn off i, turn on b
4  B I (was b, was I)		turn off b,i, order unknown :(
*/
if(state->boldlevel)
 {
   if(state->italiclevel)	//case 4
   {
     s+=do_italic_stop(state);
     s+=do_bold_stop(state);
     return 0;
   }
   else				//case 2
   {
     s+=do_bold_stop(state);
     s+=do_italic_start(state);
     return 0;
   }
 }
//no bold
if(state->italiclevel)	//case 3
 {
   s+=do_italic_stop(state);
   s+=do_bold_start(state);
   return 0;
 }
// case 1, turn on all
if(order==BI_ORD_IB)
 {
   s+=do_italic_start(state);
   s+=do_bold_start(state);
 }
else	//BI_ORD_BI
 {
   s+=do_bold_start(state);
   s+=do_italic_start(state);
 }
return 0;
}

int boldonoff_process(char *tag, char *str, struct wpstate *state,
        string &s)
{
if(state->boldlevel)	//turn off
    s+=do_bold_stop(state);
else
    s+=do_bold_start(state);
return 0;
}

int italiconoff_process(char *tag, char *str, struct wpstate *state,
        string &s)
{
if(state->italiclevel)	//turn off
    s+=do_italic_stop(state);
else
    s+=do_italic_start(state);
return 0;
}


int italicon_process(char *tag, char *str, struct wpstate *state,
    string &s)
{
s+=do_italic_start(state);
return 0;
}

int boldon_process(char *tag, char *str, struct wpstate *state,
    string &s)
{
s+=do_bold_start(state);
return 0;
}

int boldoff_process(char *tag, char *str, struct wpstate *state,
    string &s)
{
s+=do_bold_stop(state);
return 0;
}

int italicoff_process(char *tag, char *str, struct wpstate *state,
     string &s)
{
s+=do_italic_stop(state);
return 0;
}

int parastart_process(char *tag, char *str, struct wpstate *state,
    string &s)
{
s+=paragraph_stop(state);
s+=paragraph_start(state);
return 0;
}

int parastop_process(char *tag, char *str, struct wpstate *state,
    string &s)
{
s+=paragraph_stop(state);
return 0;
}



int br_process(char *tag, char *str, struct wpstate *state, string &s)
{
char *cp=tag;
int taglen=0;
while(*cp&&(*cp!='>')) {cp++;taglen++;}
s+=tag_br;
return (*cp=='>')?taglen+1:taglen;
}

int isbn_process(char *tag, char *str, struct wpstate *state, string &s)
{
int taglen=4;
char *cp=tag+taglen;
string isbn;
isbn="";
if(*cp!=' ') return -1;
taglen++;
cp++;
if(!isdigit(*cp)) return -1;
isbn+=*cp;
taglen++;
cp++;
while((*cp=='-')||isdigit(*cp))
 {
   if(*cp!='-')
     isbn+=*cp;
   else
     if(cp[1]=='-') return -1;	//avoid '---'
   cp++;
   taglen++;
   if(isbn.length()>15) return -1;
 }
if(isalpha(*cp)&&((cp[1]==' ')||(cp[1]=='\n')||(cp[1]==0)))
{
  isbn+=*cp;
  taglen++;
}
//replace isbn tag with found value and remember pointer
strcpy(str,isbn);
s+=state->separator;
s+=register_globaltag(BLOCK_TYPE_ISBN,0,str,&state->reftable);
s+=" ";
return taglen;
}

int htmltag_process(char *tag, char *str, struct wpstate *state, string &s)
/*
������� �� ����� ������ ��� '>' � ������� ��� �� < �� >
*/
{
char *cp=tag;
char ch;
int taglen=0;
while(*cp&&(*cp!='>')) {cp++;taglen++;}
if(*cp=='>') taglen++;
ch=tag[taglen];
tag[taglen]=0;
s+=tag;
tag[taglen]=ch;
return taglen;
}


/*
inline_process ������� ��������� ��������� �� ��� ��� � �� ������ ������
_�����_ ����. ���������� 0 ���� �� ����� ���� ������� ��������
������������ ��� ��� ����� ���� �����; -1 - ��� �� ������
*/

//precedence important!
struct inlinetaginfo inlinetags[]={
{"'''''",           bolditaliconoff_process},
{"'''",             boldonoff_process},
{"''",              italiconoff_process},
{"<b>",             boldon_process},
{"<i>",             italicon_process},
{"</b>",            boldoff_process},
{"</i>",            italicoff_process},
{"<br",             br_process},
{"<p>",             parastart_process},
{"</p>",            parastop_process},
{"isbn",            isbn_process},
{"<center>",        htmltag_process},
{"</center>",       htmltag_process},
{"<blockquote>",    htmltag_process},
{"</blockquote>",   htmltag_process},
//{"<td",           htmltag_process},
//{"</td",          htmltag_process},
//{"<tr",           htmltag_process},
//{"</tr",          htmltag_process},
{0,NULL}
};

string textout(char *str)
{
string s;
char *cp;
s="";
for(cp=str;*cp;cp++)
 {
   switch(*cp)
   {
     case '<':
       s+="&lt;";
       break;
     case '>':
       s+="&gt;";
       break;
     default:
       s+=*cp;
   }
 }
return s;
}

string line_process(char *str, struct wpstate *state)
{
string s;
char *cp,*icp,*textstart;
int i,tagidx,curtaglen=0,nchars;
//find closest inline tag
s="";
textstart=str;
while(*textstart)
{
  tagidx=-1;
  cp="";
  for(icp=textstart;*icp&&(tagidx==-1);icp++)
  {
    tagidx=-1;
    for(i=0;inlinetags[i].tag;i++)
    {
      curtaglen=strlen(inlinetags[i].tag);
      if(!strncasecmp(icp,inlinetags[i].tag,curtaglen))
      {
        tagidx=i;
	cp=icp;
        break;
      }
    }
  }
  if(tagidx==-1)	//clear text, just display
  {
    s+=textout(textstart);
    *textstart=0;		//��������� �����
  }
  else
  {
    if(cp>textstart) // have something to print
    {
      *cp=0;
      s+=textout(textstart);
      *cp=*inlinetags[tagidx].tag;	//restore 1st char
    }
    nchars=inlinetags[tagidx].proc(cp,cp+curtaglen,state,s);
    if(nchars==-1)	//	��������
    {
      s+=textout(inlinetags[tagidx].tag);
      nchars=curtaglen;
    }
    if(nchars==0)
      nchars=curtaglen;		//���� � ����������� ��� ����� �������������
				//� ����� ����
    textstart=cp+nchars;	//���������� ����� ����� ����
  }
}
return s;
}

int skip_empty_paragraphs(struct gtreftable *tbl)
{
int i,len;
char *cp,*ptag;
for(i=0;i<tbl->reflist_used;i++)
 {
   if(strcasecmp(tbl->reflist[i].type,BLOCK_TYPE_TEXT)) continue;
   if(!tbl->reflist[i].text||!*tbl->reflist[i].text)
     {
       tbl->reflist[i].skip=1;
       continue;
     }
   ptag=strstr(tbl->reflist[i].text,tag_paragraph_start);
   if(!ptag) continue;
   cp=ptag+strlen(tag_paragraph_start);
   while(*cp&&((*cp==' ')||(*cp=='\n'))) cp++;
   len=strlen(tag_paragraph_stop);
   if(strncmp(cp,tag_paragraph_stop,len)) continue;
   cp+=len;
   while(*cp&&((*cp==' ')||(*cp=='\n'))) cp++;
   if(*cp) continue;	//have something except ' ' or '\n' after </p>
   *ptag=0;
   if(!*tbl->reflist[i].text) tbl->reflist[i].skip=1;
 }
return tbl->reflist_used-1;
}



int parse_to_blocks(char * str, struct gtreftable *dst)
{
char *cp,*cp2,*gtagcp,*endtagcp,*linestart;
int gtagidx,starttaglen,endtaglen;
struct wpstate wpstate;
int gblen,i,found,eot,nblocks=0;
string acc,mixacc;

memset(&wpstate,0,sizeof(struct wpstate));
//init separator, find string that does not occur inside str
found=0;
for(i=0;i<999;i++)
 {
   sprintf(wpstate.separator,"@@_%i_@@",i);
   if(strstr(str,wpstate.separator)) continue;
   found=1;
   break;
 }
cp=str;
acc="";
while(*cp)	//@newline here
{
  linestart=cp;
  if(*cp=='\n')	//	/n/n
  {
    if(!wpstate.paragraph_started) {cp++;continue;}	//skip /n/n/n/n
    cp++;
    // close all inside wpstruct here
    acc+=paragraph_stop(&wpstate);
    continue;
  }
  // find global tag
  gblen=globaltag_find(cp,&gtagidx,&gtagcp,&starttaglen,
                                   &endtagcp,&endtaglen,linestart);

  if(!gblen)	//no gtag in line
  {
    cp+=line_parse(cp,acc,&wpstate);
    acc+=tag_newline;
    continue;
  }
  //�������� mixedline
  mixacc="";
  if(gtagcp>cp)	//���-�� ���� �� ������ ������
  {
    *gtagcp=0;
    mixacc+=cp;
    cp=gtagcp+gblen;
  }
  while(gblen)
  {
    if(gtagcp>cp)	//���-�� ���� ����� ������
    {
      *gtagcp=0;
      mixacc+=cp;
    }
    if(!endtagcp||!*endtagcp) eot=1; else eot=0;
    if(endtagcp) *endtagcp=0;
    if(globaltags[gtagidx].flag&BREAK_P) mixacc+="</p>"; //avoid CR injection!!
    mixacc+=globaltags[gtagidx].proc(gtagcp+starttaglen,&wpstate);
    if(eot)	//no closing tag, assume EOT
        break;
    cp=endtagcp+endtaglen;
    gblen=globaltag_find(cp,&gtagidx,&gtagcp,&starttaglen,
                                   &endtagcp,&endtaglen,linestart);
  }
  //����� ���������
  if(*cp&&(*cp!='\n'))
  {
    //���� ����� ����� �����, ��������� _��� ����������_
    cp2=cp;
    while(*cp2&&(*cp2!='\n')) cp2++;
    if(*cp2=='\n') *cp2++=0;
    mixacc+=cp;
    cp=cp2;
  }
  else if(*cp=='\n')
  {
     *cp++=0;	//����� ����� ������ ���������
  }
  /// ��� ��������� mixacc
  line_parse(mixacc,acc,&wpstate);
  acc+=tag_newline;
}
acc+=bolditalic_stopall(&wpstate);
acc+=paragraph_stop(&wpstate);
acc+=lists_stop(&wpstate);
//expand globaltag refs and make blocks
cp=acc;
gblen=strlen(wpstate.separator);
while((cp2=strstr(cp,wpstate.separator)))
 {
   *cp2=0;
   register_globaltag(BLOCK_TYPE_TEXT,0,cp,dst);
   nblocks++;
   cp2+=gblen;
   i=atoi(cp2);
   if((i>-1)&&(i<wpstate.reftable.reflist_used))
   {
     register_globaltag(wpstate.reftable.reflist[i].type,
               wpstate.reftable.reflist[i].level,
               wpstate.reftable.reflist[i].text,
               dst);
     nblocks++;
   }
   while(*cp2&&(*cp2!=' ')) cp2++;
   cp=cp2+1;	//skip ' ' after block number
 }
if(*cp)
 {
   register_globaltag(BLOCK_TYPE_TEXT,0,cp,dst);
   nblocks++;
 }
free_reftable(&wpstate.reftable);
skip_empty_paragraphs(dst);
return nblocks;
}

