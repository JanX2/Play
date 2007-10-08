# 2001 September 15
#
# The author disclaims copyright to this source code.  In place of
# a legal notice, here is a blessing:
#
#    May you do good and not evil.
#    May you find forgiveness for yourself and forgive others.
#    May you share freely, never taking more than you give.
#
#***********************************************************************
# This file implements some common TCL routines used for regression
# testing the SQLite library
#
# $Id: tester.tcl,v 1.91 2007/09/01 09:02:54 danielk1977 Exp $


set tcl_precision 15
set sqlite_pending_byte 0x0010000

# 
# Check the command-line arguments for a default soft-heap-limit.
# Store this default value in the global variable ::soft_limit and
# update the soft-heap-limit each time this script is run.  In that
# way if an individual test file changes the soft-heap-limit, it
# will be reset at the start of the next test file.
#
if {![info exists soft_limit]} {
  set soft_limit 0
  for {set i 0} {$i<[llength $argv]} {incr i} {
    if {[regexp {^--soft-heap-limit=(.+)$} [lindex $argv $i] all value]} {
      if {$value!="off"} {
        set soft_limit $value
      }
      set argv [lreplace $argv $i $i]
    }
  }
}
sqlite3_soft_heap_limit $soft_limit

# 
# Check the command-line arguments to set the memory debugger
# backtrace depth.
#
# See the sqlite3_memdebug_backtrace() function in mem2.c or
# test_malloc.c for additional information.
#
for {set i 0} {$i<[llength $argv]} {incr i} {
  if {[regexp {^--backtrace=(\d+)$} [lindex $argv $i] all value]} {
    sqlite3_memdebug_backtrace $value
    set argv [lreplace $argv $i $i]
  }
}


# Use the pager codec if it is available
#
if {[sqlite3 -has-codec] && [info command sqlite_orig]==""} {
  rename sqlite3 sqlite_orig
  proc sqlite3 {args} {
    if {[llength $args]==2 && [string index [lindex $args 0] 0]!="-"} {
      lappend args -key {xyzzy}
    }
    uplevel 1 sqlite_orig $args
  }
}


# Create a test database
#
catch {db close}
file delete -force test.db
file delete -force test.db-journal
sqlite3 db ./test.db
set ::DB [sqlite3_connection_pointer db]
if {[info exists ::SETUP_SQL]} {
  db eval $::SETUP_SQL
}

# Abort early if this script has been run before.
#
if {[info exists nTest]} return

# Set the test counters to zero
#
set nErr 0
set nTest 0
set skip_test 0
set failList {}
set maxErr 1000
if {![info exists speedTest]} {
  set speedTest 0
}

# Invoke the do_test procedure to run a single test 
#
proc do_test {name cmd expected} {
  global argv nErr nTest skip_test maxErr
  sqlite3_memdebug_settitle $name
  if {$skip_test} {
    set skip_test 0
    return
  }
  if {[llength $argv]==0} { 
    set go 1
  } else {
    set go 0
    foreach pattern $argv {
      if {[string match $pattern $name]} {
        set go 1
        break
      }
    }
  }
  if {!$go} return
  incr nTest
  puts -nonewline $name...
  flush stdout
  if {[catch {uplevel #0 "$cmd;\n"} result]} {
    puts "\nError: $result"
    incr nErr
    lappend ::failList $name
    if {$nErr>$maxErr} {puts "*** Giving up..."; finalize_testing}
  } elseif {[string compare $result $expected]} {
    puts "\nExpected: \[$expected\]\n     Got: \[$result\]"
    incr nErr
    lappend ::failList $name
    if {$nErr>=$maxErr} {puts "*** Giving up..."; finalize_testing}
  } else {
    puts " Ok"
  }
  flush stdout
}

# Run an SQL script.  
# Return the number of microseconds per statement.
#
proc speed_trial {name numstmt units sql} {
  puts -nonewline [format {%-21.21s } $name...]
  flush stdout
  set speed [time {sqlite3_exec_nr db $sql}]
  set tm [lindex $speed 0]
  set rate [expr {1000000.0*$numstmt/$tm}]
  set u2 $units/s
  puts [format {%12d uS %20.5f %s} $tm $rate $u2]
  global total_time
  set total_time [expr {$total_time+$tm}]
}
proc speed_trial_init {name} {
  global total_time
  set total_time 0
}
proc speed_trial_summary {name} {
  global total_time
  puts [format {%-21.21s %12d uS TOTAL} $name $total_time]
}

# Run this routine last
#
proc finish_test {} {
  finalize_testing
}
proc finalize_testing {} {
  global nTest nErr sqlite_open_file_count

  catch {db close}
  catch {db2 close}
  catch {db3 close}

  sqlite3 db {}
  # sqlite3_clear_tsd_memdebug
  db close
  set heaplimit [sqlite3_soft_heap_limit]
  if {$heaplimit!=$::soft_limit} {
    puts "soft-heap-limit changed by this script\
          from $::soft_limit to $heaplimit"
  } elseif {$heaplimit!="" && $heaplimit>0} {
    puts "soft-heap-limit set to $heaplimit"
  }
  sqlite3_soft_heap_limit 0
  incr nTest
  puts "$nErr errors out of $nTest tests"
  if {$nErr>0} {
    puts "Failures on these tests: $::failList"
  }
  if {$nErr>0 && ![working_64bit_int]} {
    puts "******************************************************************"
    puts "N.B.:  The version of TCL that you used to build this test harness"
    puts "is defective in that it does not support 64-bit integers.  Some or"
    puts "all of the test failures above might be a result from this defect"
    puts "in your TCL build."
    puts "******************************************************************"
  }
  if {$sqlite_open_file_count} {
    puts "$sqlite_open_file_count files were left open"
    incr nErr
  }
  if {[sqlite3_memory_used]>0} {
    puts "Unfreed memory: [sqlite3_memory_used] bytes"
    incr nErr
    ifcapable memdebug {
      puts "Writing unfreed memory log to \"./memleak.txt\""
      sqlite3_memdebug_dump ./memleak.txt
    }
  } else {
    puts "All memory allocations freed - no leaks"
  }
  puts "Maximum memory usage: [sqlite3_memory_highwater] bytes"
  foreach f [glob -nocomplain test.db-*-journal] {
    file delete -force $f
  }
  foreach f [glob -nocomplain test.db-mj*] {
    file delete -force $f
  }
  exit [expr {$nErr>0}]
}

# A procedure to execute SQL
#
proc execsql {sql {db db}} {
  # puts "SQL = $sql"
  uplevel [list $db eval $sql]
}

# Execute SQL and catch exceptions.
#
proc catchsql {sql {db db}} {
  # puts "SQL = $sql"
  set r [catch {$db eval $sql} msg]
  lappend r $msg
  return $r
}

# Do an VDBE code dump on the SQL given
#
proc explain {sql {db db}} {
  puts ""
  puts "addr  opcode        p1       p2     p3             "
  puts "----  ------------  ------  ------  ---------------"
  $db eval "explain $sql" {} {
    puts [format {%-4d  %-12.12s  %-6d  %-6d  %s} $addr $opcode $p1 $p2 $p3]
  }
}

# Another procedure to execute SQL.  This one includes the field
# names in the returned list.
#
proc execsql2 {sql} {
  set result {}
  db eval $sql data {
    foreach f $data(*) {
      lappend result $f $data($f)
    }
  }
  return $result
}

# Use the non-callback API to execute multiple SQL statements
#
proc stepsql {dbptr sql} {
  set sql [string trim $sql]
  set r 0
  while {[string length $sql]>0} {
    if {[catch {sqlite3_prepare $dbptr $sql -1 sqltail} vm]} {
      return [list 1 $vm]
    }
    set sql [string trim $sqltail]
#    while {[sqlite_step $vm N VAL COL]=="SQLITE_ROW"} {
#      foreach v $VAL {lappend r $v}
#    }
    while {[sqlite3_step $vm]=="SQLITE_ROW"} {
      for {set i 0} {$i<[sqlite3_data_count $vm]} {incr i} {
        lappend r [sqlite3_column_text $vm $i]
      }
    }
    if {[catch {sqlite3_finalize $vm} errmsg]} {
      return [list 1 $errmsg]
    }
  }
  return $r
}

# Delete a file or directory
#
proc forcedelete {filename} {
  if {[catch {file delete -force $filename}]} {
    exec rm -rf $filename
  }
}

# Do an integrity check of the entire database
#
proc integrity_check {name} {
  ifcapable integrityck {
    do_test $name {
      execsql {PRAGMA integrity_check}
    } {ok}
  }
}

# Evaluate a boolean expression of capabilities.  If true, execute the
# code.  Omit the code if false.
#
proc ifcapable {expr code {else ""} {elsecode ""}} {
  regsub -all {[a-z_0-9]+} $expr {$::sqlite_options(&)} e2
  if ($e2) {
    set c [catch {uplevel 1 $code} r]
  } else {
    set c [catch {uplevel 1 $elsecode} r]
  }
  return -code $c $r
}

# This proc execs a seperate process that crashes midway through executing
# the SQL script $sql on database test.db.
#
# The crash occurs during a sync() of file $crashfile. When the crash
# occurs a random subset of all unsynced writes made by the process are
# written into the files on disk. Argument $crashdelay indicates the
# number of file syncs to wait before crashing.
#
# The return value is a list of two elements. The first element is a
# boolean, indicating whether or not the process actually crashed or
# reported some other error. The second element in the returned list is the
# error message. This is "child process exited abnormally" if the crash
# occured.
#
#   crashsql -delay CRASHDELAY -file CRASHFILE ?-blocksize BLOCKSIZE? $sql
#
proc crashsql {args} {
  if {$::tcl_platform(platform)!="unix"} {
    error "crashsql should only be used on unix"
  }

  set blocksize ""
  set crashdelay 1
  set crashfile ""
  set dc ""
  set sql [lindex $args end]
  
  for {set ii 0} {$ii < [llength $args]-1} {incr ii 2} {
    set z [lindex $args $ii]
    set n [string length $z]
    set z2 [lindex $args [expr $ii+1]]

    if     {$n>1 && [string first $z -delay]==0}     {set crashdelay $z2} \
    elseif {$n>1 && [string first $z -file]==0}      {set crashfile $z2}  \
    elseif {$n>1 && [string first $z -blocksize]==0} {set blocksize "-s $z2" } \
    elseif {$n>1 && [string first $z -characteristics]==0} {set dc "-c {$z2}" } \
    else   { error "Unrecognized option: $z" }
  }

  if {$crashfile eq ""} {
    error "Compulsory option -file missing"
  }

  set cfile [file join [pwd] $crashfile]

  set f [open crash.tcl w]
  puts $f "sqlite3_crash_enable 1"
  puts $f "sqlite3_crashparams $blocksize $dc $crashdelay $cfile"
  puts $f "set sqlite_pending_byte $::sqlite_pending_byte"
  puts $f "sqlite3 db test.db -vfs crash"

  # This block sets the cache size of the main database to 10
  # pages. This is done in case the build is configured to omit
  # "PRAGMA cache_size".
  puts $f {db eval {SELECT * FROM sqlite_master;}}
  puts $f {set bt [btree_from_db db]}
  puts $f {btree_set_cache_size $bt 10}

  puts $f "db eval {"
  puts $f   "$sql"
  puts $f "}"
  close $f

  set r [catch {
    exec [info nameofexec] crash.tcl >@stdout
  } msg]
  lappend r $msg
}

# Usage: do_ioerr_test <test number> <options...>
#
# This proc is used to implement test cases that check that IO errors
# are correctly handled. The first argument, <test number>, is an integer 
# used to name the tests executed by this proc. Options are as follows:
#
#     -tclprep          TCL script to run to prepare test.
#     -sqlprep          SQL script to run to prepare test.
#     -tclbody          TCL script to run with IO error simulation.
#     -sqlbody          TCL script to run with IO error simulation.
#     -exclude          List of 'N' values not to test.
#     -erc              Use extended result codes
#     -persist          Make simulated I/O errors persistent
#     -start            Value of 'N' to begin with (default 1)
#
#     -cksum            Boolean. If true, test that the database does
#                       not change during the execution of the test case.
#
proc do_ioerr_test {testname args} {

  set ::ioerropts(-start) 1
  set ::ioerropts(-cksum) 0
  set ::ioerropts(-erc) 0
  set ::ioerropts(-count) 100000000
  set ::ioerropts(-persist) 1
  array set ::ioerropts $args

  set ::go 1
  for {set n $::ioerropts(-start)} {$::go} {incr n} {
    set ::TN $n
    incr ::ioerropts(-count) -1
    if {$::ioerropts(-count)<0} break
 
    # Skip this IO error if it was specified with the "-exclude" option.
    if {[info exists ::ioerropts(-exclude)]} {
      if {[lsearch $::ioerropts(-exclude) $n]!=-1} continue
    }

    # Delete the files test.db and test2.db, then execute the TCL and 
    # SQL (in that order) to prepare for the test case.
    do_test $testname.$n.1 {
      set ::sqlite_io_error_pending 0
      catch {db close}
      catch {file delete -force test.db}
      catch {file delete -force test.db-journal}
      catch {file delete -force test2.db}
      catch {file delete -force test2.db-journal}
      set ::DB [sqlite3 db test.db; sqlite3_connection_pointer db]
      sqlite3_extended_result_codes $::DB $::ioerropts(-erc)
      if {[info exists ::ioerropts(-tclprep)]} {
        eval $::ioerropts(-tclprep)
      }
      if {[info exists ::ioerropts(-sqlprep)]} {
        execsql $::ioerropts(-sqlprep)
      }
      expr 0
    } {0}

    # Read the 'checksum' of the database.
    if {$::ioerropts(-cksum)} {
      set checksum [cksum]
    }
  
    # Set the Nth IO error to fail.
    do_test $testname.$n.2 [subst {
      set ::sqlite_io_error_persist $::ioerropts(-persist)
      set ::sqlite_io_error_pending $n
    }] $n
  
    # Create a single TCL script from the TCL and SQL specified
    # as the body of the test.
    set ::ioerrorbody {}
    if {[info exists ::ioerropts(-tclbody)]} {
      append ::ioerrorbody "$::ioerropts(-tclbody)\n"
    }
    if {[info exists ::ioerropts(-sqlbody)]} {
      append ::ioerrorbody "db eval {$::ioerropts(-sqlbody)}"
    }

    # Execute the TCL Script created in the above block. If
    # there are at least N IO operations performed by SQLite as
    # a result of the script, the Nth will fail.
    do_test $testname.$n.3 {
      set r [catch $::ioerrorbody msg]
      set rc [sqlite3_errcode $::DB]
      if {$::ioerropts(-erc)} {
        # If we are in extended result code mode, make sure all of the
        # IOERRs we get back really do have their extended code values.
        # If an extended result code is returned, the sqlite3_errcode
        # TCLcommand will return a string of the form:  SQLITE_IOERR+nnnn
        # where nnnn is a number
        if {[regexp {^SQLITE_IOERR} $rc] && ![regexp {IOERR\+\d} $rc]} {
          return $rc
        }
      } else {
        # If we are not in extended result code mode, make sure no
        # extended error codes are returned.
        if {[regexp {\+\d} $rc]} {
          return $rc
        }
      }
      # The test repeats as long as $::go is true.  
      set ::go [expr {$::sqlite_io_error_pending<=0}]
      set s [expr $::sqlite_io_error_hit==0]
      set ::sqlite_io_error_hit 0

      # One of two things must have happened. either
      #   1.  We never hit the IO error and the SQL returned OK
      #   2.  An IO error was hit and the SQL failed
      #
      expr { ($s && !$r && !$::go) || (!$s && $r && $::go) }
    } {1}

    # If an IO error occured, then the checksum of the database should
    # be the same as before the script that caused the IO error was run.
    if {$::go && $::ioerropts(-cksum)} {
      do_test $testname.$n.4 {
        catch {db close}
        set ::DB [sqlite3 db test.db; sqlite3_connection_pointer db]
        cksum
      } $checksum
    }

    set ::sqlite_io_error_pending 0
    if {[info exists ::ioerropts(-cleanup)]} {
      catch $::ioerropts(-cleanup)
    }
  }
  set ::sqlite_io_error_pending 0
  set ::sqlite_io_error_persist 0
  unset ::ioerropts
}

# Return a checksum based on the contents of database 'db'.
#
proc cksum {{db db}} {
  set txt [$db eval {
      SELECT name, type, sql FROM sqlite_master order by name
  }]\n
  foreach tbl [$db eval {
      SELECT name FROM sqlite_master WHERE type='table' order by name
  }] {
    append txt [$db eval "SELECT * FROM $tbl"]\n
  }
  foreach prag {default_synchronous default_cache_size} {
    append txt $prag-[$db eval "PRAGMA $prag"]\n
  }
  set cksum [string length $txt]-[md5 $txt]
  # puts $cksum-[file size test.db]
  return $cksum
}

# Copy file $from into $to. This is used because some versions of
# TCL for windows (notably the 8.4.1 binary package shipped with the
# current mingw release) have a broken "file copy" command.
#
proc copy_file {from to} {
  if {$::tcl_platform(platform)=="unix"} {
    file copy -force $from $to
  } else {
    set f [open $from]
    fconfigure $f -translation binary
    set t [open $to w]
    fconfigure $t -translation binary
    puts -nonewline $t [read $f [file size $from]]
    close $t
    close $f
  }
}

# If the library is compiled with the SQLITE_DEFAULT_AUTOVACUUM macro set
# to non-zero, then set the global variable $AUTOVACUUM to 1.
set AUTOVACUUM $sqlite_options(default_autovacuum)
