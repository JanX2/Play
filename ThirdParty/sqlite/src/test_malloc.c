/*
** 2007 August 15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
**
** This file contains code used to implement test interfaces to the
** memory allocation subsystem.
**
** $Id: test_malloc.c,v 1.8 2007/09/03 07:31:10 danielk1977 Exp $
*/
#include "sqliteInt.h"
#include "tcl.h"
#include <stdlib.h>
#include <string.h>
#include <assert.h>

/*
** Transform pointers to text and back again
*/
static void pointerToText(void *p, char *z){
  static const char zHex[] = "0123456789abcdef";
  int i, k;
  unsigned int u;
  sqlite3_uint64 n;
  if( sizeof(n)==sizeof(p) ){
    memcpy(&n, &p, sizeof(p));
  }else if( sizeof(u)==sizeof(p) ){
    memcpy(&u, &p, sizeof(u));
    n = u;
  }else{
    assert( 0 );
  }
  for(i=0, k=sizeof(p)*2-1; i<sizeof(p)*2; i++, k--){
    z[k] = zHex[n&0xf];
    n >>= 4;
  }
  z[sizeof(p)*2] = 0;
}
static int hexToInt(int h){
  if( h>='0' && h<='9' ){
    return h - '0';
  }else if( h>='a' && h<='f' ){
    return h - 'a' + 10;
  }else{
    return -1;
  }
}
static int textToPointer(const char *z, void **pp){
  sqlite3_uint64 n = 0;
  int i;
  unsigned int u;
  for(i=0; i<sizeof(void*)*2 && z[0]; i++){
    int v;
    v = hexToInt(*z++);
    if( v<0 ) return TCL_ERROR;
    n = n*16 + v;
  }
  if( *z!=0 ) return TCL_ERROR;
  if( sizeof(n)==sizeof(*pp) ){
    memcpy(pp, &n, sizeof(n));
  }else if( sizeof(u)==sizeof(*pp) ){
    u = (unsigned int)n;
    memcpy(pp, &u, sizeof(u));
  }else{
    assert( 0 );
  }
  return TCL_OK;
}

/*
** Usage:    sqlite3_malloc  NBYTES
**
** Raw test interface for sqlite3_malloc().
*/
static int test_malloc(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  int nByte;
  void *p;
  char zOut[100];
  if( objc!=2 ){
    Tcl_WrongNumArgs(interp, 1, objv, "NBYTES");
    return TCL_ERROR;
  }
  if( Tcl_GetIntFromObj(interp, objv[1], &nByte) ) return TCL_ERROR;
  p = sqlite3_malloc((unsigned)nByte);
  pointerToText(p, zOut);
  Tcl_AppendResult(interp, zOut, NULL);
  return TCL_OK;
}

/*
** Usage:    sqlite3_realloc  PRIOR  NBYTES
**
** Raw test interface for sqlite3_realloc().
*/
static int test_realloc(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  int nByte;
  void *pPrior, *p;
  char zOut[100];
  if( objc!=3 ){
    Tcl_WrongNumArgs(interp, 1, objv, "PRIOR NBYTES");
    return TCL_ERROR;
  }
  if( Tcl_GetIntFromObj(interp, objv[2], &nByte) ) return TCL_ERROR;
  if( textToPointer(Tcl_GetString(objv[1]), &pPrior) ){
    Tcl_AppendResult(interp, "bad pointer: ", Tcl_GetString(objv[1]), (char*)0);
    return TCL_ERROR;
  }
  p = sqlite3_realloc(pPrior, (unsigned)nByte);
  pointerToText(p, zOut);
  Tcl_AppendResult(interp, zOut, NULL);
  return TCL_OK;
}


/*
** Usage:    sqlite3_free  PRIOR
**
** Raw test interface for sqlite3_free().
*/
static int test_free(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  void *pPrior;
  if( objc!=2 ){
    Tcl_WrongNumArgs(interp, 1, objv, "PRIOR");
    return TCL_ERROR;
  }
  if( textToPointer(Tcl_GetString(objv[1]), &pPrior) ){
    Tcl_AppendResult(interp, "bad pointer: ", Tcl_GetString(objv[1]), (char*)0);
    return TCL_ERROR;
  }
  sqlite3_free(pPrior);
  return TCL_OK;
}

/*
** Usage:    sqlite3_memory_used
**
** Raw test interface for sqlite3_memory_used().
*/
static int test_memory_used(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  Tcl_SetObjResult(interp, Tcl_NewWideIntObj(sqlite3_memory_used()));
  return TCL_OK;
}

/*
** Usage:    sqlite3_memory_highwater ?RESETFLAG?
**
** Raw test interface for sqlite3_memory_highwater().
*/
static int test_memory_highwater(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  int resetFlag = 0;
  if( objc!=1 && objc!=2 ){
    Tcl_WrongNumArgs(interp, 1, objv, "?RESET?");
    return TCL_ERROR;
  }
  if( objc==2 ){
    if( Tcl_GetBooleanFromObj(interp, objv[1], &resetFlag) ) return TCL_ERROR;
  } 
  Tcl_SetObjResult(interp, 
     Tcl_NewWideIntObj(sqlite3_memory_highwater(resetFlag)));
  return TCL_OK;
}

/*
** Usage:    sqlite3_memdebug_backtrace DEPTH
**
** Set the depth of backtracing.  If SQLITE_MEMDEBUG is not defined
** then this routine is a no-op.
*/
static int test_memdebug_backtrace(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  int depth;
  if( objc!=2 ){
    Tcl_WrongNumArgs(interp, 1, objv, "DEPT");
    return TCL_ERROR;
  }
  if( Tcl_GetIntFromObj(interp, objv[1], &depth) ) return TCL_ERROR;
#ifdef SQLITE_MEMDEBUG
  {
    extern void sqlite3_memdebug_backtrace(int);
    sqlite3_memdebug_backtrace(depth);
  }
#endif
  return TCL_OK;
}

/*
** Usage:    sqlite3_memdebug_dump  FILENAME
**
** Write a summary of unfreed memory to FILENAME.
*/
static int test_memdebug_dump(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  if( objc!=2 ){
    Tcl_WrongNumArgs(interp, 1, objv, "FILENAME");
    return TCL_ERROR;
  }
#ifdef SQLITE_MEMDEBUG
  {
    extern void sqlite3_memdebug_dump(const char*);
    sqlite3_memdebug_dump(Tcl_GetString(objv[1]));
  }
#endif
  return TCL_OK;
}


/*
** Usage:    sqlite3_memdebug_fail  COUNTER  ?OPTIONS?
**
** where options are:
**
**     -repeat    <boolean>
**     -benigncnt <varname>
**
** Arrange for a simulated malloc() failure after COUNTER successes.
** If REPEAT is 1 then all subsequent malloc()s fail.   If REPEAT is
** 0 then only a single failure occurs.
**
** Each call to this routine overrides the prior counter value.
** This routine returns the number of simulated failures that have
** happened since the previous call to this routine.
**
** To disable simulated failures, use a COUNTER of -1.
*/
static int test_memdebug_fail(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  int ii;
  int iFail;
  int iRepeat = -1;
  Tcl_Obj *pBenignCnt = 0;

  int nFail = 0;

  if( objc<2 ){
    Tcl_WrongNumArgs(interp, 1, objv, "COUNTER ?OPTIONS?");
    return TCL_ERROR;
  }
  if( Tcl_GetIntFromObj(interp, objv[1], &iFail) ) return TCL_ERROR;

  for(ii=2; ii<objc; ii+=2){
    int nOption;
    char *zOption = Tcl_GetStringFromObj(objv[ii], &nOption);
    char *zErr = 0;

    if( nOption>1 && strncmp(zOption, "-repeat", nOption)==0 ){
      if( ii==(objc-1) ){
        zErr = "option requires an argument: ";
      }else{
        if( Tcl_GetIntFromObj(interp, objv[ii+1], &iRepeat) ){
          return TCL_ERROR;
        }
      }
    }else if( nOption>1 && strncmp(zOption, "-benigncnt", nOption)==0 ){
      if( ii==(objc-1) ){
        zErr = "option requires an argument: ";
      }else{
        pBenignCnt = objv[ii+1];
      }
    }else{
      zErr = "unknown option: ";
    }

    if( zErr ){
      Tcl_AppendResult(interp, zErr, zOption, 0);
      return TCL_ERROR;
    }
  }
  
#ifdef SQLITE_MEMDEBUG
  {
    extern int sqlite3_memdebug_fail(int,int,int*);
    int iBenignCnt;
    nFail = sqlite3_memdebug_fail(iFail, iRepeat, &iBenignCnt);
    if( pBenignCnt ){
      Tcl_ObjSetVar2(interp, pBenignCnt, 0, Tcl_NewIntObj(iBenignCnt), 0);
    }
  }
#endif
  Tcl_SetObjResult(interp, Tcl_NewIntObj(nFail));
  return TCL_OK;
}

/*
** Usage:    sqlite3_memdebug_pending
**
** Return the number of malloc() calls that will succeed before a 
** simulated failure occurs. A negative return value indicates that
** no malloc() failure is scheduled.
*/
static int test_memdebug_pending(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  if( objc!=1 ){
    Tcl_WrongNumArgs(interp, 1, objv, "");
    return TCL_ERROR;
  }

#ifdef SQLITE_MEMDEBUG
  {
    extern int sqlite3_memdebug_pending();
    Tcl_SetObjResult(interp, Tcl_NewIntObj(sqlite3_memdebug_pending()));
  }
#endif
  return TCL_OK;
}


/*
** Usage:    sqlite3_memdebug_settitle TITLE
**
** Set a title string stored with each allocation.  The TITLE is
** typically the name of the test that was running when the
** allocation occurred.  The TITLE is stored with the allocation
** and can be used to figure out which tests are leaking memory.
**
** Each title overwrite the previous.
*/
static int test_memdebug_settitle(
  void * clientData,
  Tcl_Interp *interp,
  int objc,
  Tcl_Obj *CONST objv[]
){
  const char *zTitle;
  if( objc!=2 ){
    Tcl_WrongNumArgs(interp, 1, objv, "TITLE");
    return TCL_ERROR;
  }
  zTitle = Tcl_GetString(objv[1]);
#ifdef SQLITE_MEMDEBUG
  {
    extern int sqlite3_memdebug_settitle(const char*);
    sqlite3_memdebug_settitle(zTitle);
  }
#endif
  return TCL_OK;
}


/*
** Register commands with the TCL interpreter.
*/
int Sqlitetest_malloc_Init(Tcl_Interp *interp){
  static struct {
     char *zName;
     Tcl_ObjCmdProc *xProc;
  } aObjCmd[] = {
     { "sqlite3_malloc",             test_malloc                   },
     { "sqlite3_realloc",            test_realloc                  },
     { "sqlite3_free",               test_free                     },
     { "sqlite3_memory_used",        test_memory_used              },
     { "sqlite3_memory_highwater",   test_memory_highwater         },
     { "sqlite3_memdebug_backtrace", test_memdebug_backtrace       },
     { "sqlite3_memdebug_dump",      test_memdebug_dump            },
     { "sqlite3_memdebug_fail",      test_memdebug_fail            },
     { "sqlite3_memdebug_pending",   test_memdebug_pending         },
     { "sqlite3_memdebug_settitle",  test_memdebug_settitle        },
  };
  int i;
  for(i=0; i<sizeof(aObjCmd)/sizeof(aObjCmd[0]); i++){
    Tcl_CreateObjCommand(interp, aObjCmd[i].zName, aObjCmd[i].xProc, 0, 0);
  }
  return TCL_OK;
}
