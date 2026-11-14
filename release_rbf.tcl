# ============================================================================
#  Atari G1 for MiSTer
#  release_rbf.tcl -- after a compile: date the core into releases/, run the
#                     clock report, and write the failing paths if timing failed
#
#  Quartus runs this after every compile (POST_FLOW_SCRIPT_FILE in the .qsf),
#  from the project folder.
#
#  Release. For the production revision only, and only when this compile got
#  through the Assembler, it moves
#      output_files/Arcade-Atari-G1.rbf
#  to  releases/Arcade-Atari-G1_YYYYMMDD.rbf
#  The date is the core's own build date (build_id.v, the OSD version), so
#  the file name and the OSD agree. A core already released under that name
#  is replaced; older dated cores are left alone.
#
#  Any other revision is skipped. A compile that fails before the Assembler
#  leaves nothing to release. Failed timing is reported as a warning; the core is
#  still released.
#
#  Clock report. For whichever revision was compiled, when the compile got through the
#  Assembler, it runs tools/clock_report.tcl on the compile's own Timing
#  Analyzer and Fitter reports and writes
#      output_files/<revision>.clock_report.txt
#  The three verdicts (clock rates, timing met, SDRAM I/O constrained) and
#  every failed check go to the Messages window. Where the compile did not
#  finish, or its reports are not this compile's, the file says it was not run
#  instead of keeping an old report. Without tools/clock_report.tcl there is no
#  report. Nothing about the report can stop the release.
#
#  Path report. The clock report reads the compile's summary tables, which say
#  that timing failed but not which paths. So when the compile got through the
#  Assembler and its Timing Analyzer summary has a negative slack, this runs
#      quartus_sta -t tools/timing_report.tcl <revision> output_files/<revision>.timing_report.txt
#  after the release and the clock report: the worst setup and hold paths in
#  full, one line per failing endpoint, and the SDRAM read-capture crossings.
#  It takes a minute or two. When timing was met the file says so; where the
#  compile did not finish, or its reports are not this compile's, it says it
#  was not run; either way an older report is replaced, never kept. If
#  quartus_sta cannot be run, a warning gives the command to run by hand.
#  Without tools/timing_report.tcl there is no report. Nothing about the
#  report can stop the release.
# ============================================================================

set production  "Arcade-Atari-G1"
set release_dir "releases"
set report_tcl  "tools/clock_report.tcl"
set path_tcl    "tools/timing_report.tcl"

proc note {msg} { post_message -type info    "release_rbf: $msg" }
proc warn {msg} { post_message -type warning "release_rbf: $msg" }
proc report_note {msg} { post_message -type info    "clock_report: $msg" }
proc report_warn {msg} { post_message -type warning "clock_report: $msg" }
proc path_note {msg} { post_message -type info    "timing_report: $msg" }
proc path_warn {msg} { post_message -type warning "timing_report: $msg" }

proc slurp {path} {
    set f [open $path r]
    set data [read $f]
    close $f
    return $data
}

# The .qsf's settings with its comment lines removed.
proc qsf_settings {revision} {
    set out {}
    if {![file exists "$revision.qsf"]} { return $out }
    foreach line [split [slurp "$revision.qsf"] "\n"] {
        if {![regexp {^\s*#} $line]} { lappend out $line }
    }
    return [join $out "\n"]
}

# Where the compile put its files.
proc output_dir {qsf} {
    set outdir "."
    regexp {(?n)^\s*set_global_assignment\s+-name\s+PROJECT_OUTPUT_DIRECTORY\s+"?([^"\s]+)"?} \
        $qsf -> outdir
    return $outdir
}

# Did this compile get through the Assembler? Its report must be newer than the
# Fitter's and say Successful. Returns ok, missing (no report), stale (older
# than the Fitter's: the Assembler did not run this time) or failed.
proc assembler_state {outdir revision} {
    set asm "$outdir/$revision.asm.rpt"
    set fit "$outdir/$revision.fit.rpt"
    if {![file exists $asm]} { return missing }
    if {[file exists $fit] && [file mtime $asm] < [file mtime $fit]} { return stale }
    if {![regexp {Assembler Status\s*;\s*Successful} [slurp $asm]]} { return failed }
    return ok
}

proc release {revision} {
    global production release_dir

    if {$revision ne $production} {
        note "$revision is not the production build ($production); nothing released"
        return
    }
    set qsf [qsf_settings $revision]

    set outdir [output_dir $qsf]
    set asm "$outdir/$revision.asm.rpt"
    set rbf "$outdir/$revision.rbf"
    switch [assembler_state $outdir $revision] {
        missing {
            note "no Assembler report ($asm); nothing released"
            return
        }
        stale {
            note "the Assembler did not run in this compile; nothing released"
            return
        }
        failed {
            warn "the Assembler did not succeed; nothing released"
            return
        }
    }
    if {![file exists $rbf]} {
        warn "$rbf not found; nothing released (check GENERATE_RBF_FILE)"
        return
    }

    # The date the core reports on the OSD, else today's.
    set date [clock format [clock seconds] -format %Y%m%d]
    if {[file exists "build_id.v"] &&
        [regexp {BUILD_DATE\s+"(\d{6})"} [slurp "build_id.v"] -> yymmdd]} {
        set date "20$yymmdd"
    }

    file mkdir $release_dir
    set dest "$release_dir/${revision}_$date.rbf"
    if {[catch {file rename -force $rbf $dest} err]} {
        warn "could not move $rbf to $dest: $err"
        return
    }
    note "released $rbf as $dest"

    # Timing: any negative slack in the Timing Analyzer summary.
    set sta "$outdir/$revision.sta.summary"
    if {[file exists $sta] && [regexp {Slack\s*:\s*-} [slurp $sta]]} {
        warn "timing requirements were not met (see $outdir/$revision.sta.rpt); released anyway"
    }
}

# Replace an earlier report with a note saying this compile has none.
proc report_skipped {out reason} {
    catch {
        set f [open $out w]
        puts $f "CLOCK REPORT NOT RUN FOR THIS COMPILE"
        puts $f $reason
        close $f
    }
}

proc clock_report {revision} {
    global report_tcl

    if {![file exists $report_tcl]} {
        report_note "$report_tcl not found; no clock report"
        return
    }
    set outdir [output_dir [qsf_settings $revision]]
    set sta "$outdir/$revision.sta.rpt"
    set fit "$outdir/$revision.fit.rpt"
    set out "$outdir/$revision.clock_report.txt"

    # Only a compile that got through the Assembler, and only reports that
    # belong to it: the Timing Analyzer's must be newer than the Fitter's.
    if {[assembler_state $outdir $revision] ne "ok"} {
        set reason "this compile did not get through the Assembler"
        report_skipped $out $reason
        report_note "skipped: $reason"
        return
    }
    if {![file exists $sta]} {
        set reason "$sta not found (the Timing Analyzer has not written it)"
        report_skipped $out $reason
        report_warn "skipped: $reason"
        return
    }
    if {[file exists $fit] && [file mtime $sta] < [file mtime $fit]} {
        set reason "$sta is older than $fit, so it belongs to an earlier compile"
        report_skipped $out $reason
        report_warn "skipped: $reason"
        return
    }

    set ::cr_library_mode 1
    uplevel #0 [list source $report_tcl]
    set argl [list --rpt $sta --out $out --quiet]
    if {[file exists $fit]} { lappend argl --fit $fit }
    set rc [cr::run $argl]
    if {$rc == 2} {
        if {$cr::run_error ne ""} {
            report_warn "stopped on a Tcl error: $cr::run_error (see $out)"
        } else {
            report_warn "could not read $sta"
        }
        return
    }

    foreach {key text} {
        rates  "clock rates match the board"
        timing "timing met (as constrained)"
        sdram  "SDRAM I/O constrained"
    } {
        if {![info exists cr::verdict($key)]} continue
        if {$cr::verdict($key) eq "YES"} {
            report_note "$text: YES"
        } else {
            report_warn "$text: NO"
        }
    }
    set shown 8
    foreach label [lrange $cr::fail_labels 0 [expr {$shown - 1}]] {
        report_warn "FAIL: $label"
    }
    if {[llength $cr::fail_labels] > $shown} {
        report_warn "and [expr {[llength $cr::fail_labels] - $shown}] more failed checks"
    }
    report_note "full report: $out"
}

# --------------------------------------------------------------------- path report

# A report file that says why there is no report, replacing any older one.
proc path_file_note {out title reason} {
    catch {
        set f [open $out w]
        puts $f $title
        puts $f $reason
        close $f
    }
}

# Why this compile's reports cannot be used, or "" when they can: the
# Assembler must have succeeded and the Timing Analyzer's report must be this
# compile's (newer than the Fitter's).
proc reports_problem {outdir revision} {
    set sta "$outdir/$revision.sta.rpt"
    set fit "$outdir/$revision.fit.rpt"
    if {[assembler_state $outdir $revision] ne "ok"} {
        return "this compile did not get through the Assembler"
    }
    if {![file exists $sta]} {
        return "$sta not found (the Timing Analyzer has not written it)"
    }
    if {[file exists $fit] && [file mtime $sta] < [file mtime $fit]} {
        return "$sta is older than $fit, so it belongs to an earlier compile"
    }
    return ""
}

# Did the Timing Analyzer's summary report a negative slack? With no summary
# to read the answer is unknown, and unknown counts as yes.
proc timing_failed {outdir revision} {
    set summary "$outdir/$revision.sta.summary"
    if {![file exists $summary]} { return 1 }
    return [regexp {Slack\s*:\s*-} [slurp $summary]]
}

# quartus_sta sits beside the quartus_sh that is running this script.
proc find_sta {} {
    if {[info exists ::quartus(binpath)]} {
        foreach name {quartus_sta quartus_sta.exe} {
            set p [file join $::quartus(binpath) $name]
            if {[file exists $p]} { return $p }
        }
    }
    return quartus_sta
}

# The last n non-empty lines of a command's output, on one line.
proc tail_lines {text n} {
    set keep {}
    foreach line [split $text "\n"] {
        set line [string trim $line]
        if {$line ne ""} { lappend keep $line }
    }
    return [join [lrange $keep end-[expr {$n - 1}] end] " | "]
}

proc path_report {revision} {
    global path_tcl

    if {![file exists $path_tcl]} {
        path_note "$path_tcl not found; no path report"
        return
    }
    set outdir [output_dir [qsf_settings $revision]]
    set out "$outdir/$revision.timing_report.txt"
    set manual "quartus_sta -t $path_tcl $revision"

    set problem [reports_problem $outdir $revision]
    if {$problem ne ""} {
        path_file_note $out "PATH REPORT NOT RUN FOR THIS COMPILE" $problem
        path_note "skipped: $problem"
        return
    }
    if {![timing_failed $outdir $revision]} {
        path_file_note $out "NO PATH REPORT: TIMING WAS MET" \
            "The Timing Analyzer reported no negative slack, so there are no failing paths to list.\nFor the worst paths anyway: $manual"
        path_note "timing met; no failing paths to write"
        return
    }

    # If quartus_sta cannot even start, this note is what stays, not an old report.
    path_file_note $out "PATH REPORT NOT FINISHED" \
        "quartus_sta was started on this compile and did not finish writing this file.\nRun it by hand: $manual"
    path_note "timing failed: writing the failing paths to $out (a minute or two)"

    set cmd [list [find_sta] -t $path_tcl $revision $out]
    if {[catch {eval exec $cmd 2>@1} log]} {
        path_warn "quartus_sta stopped: [tail_lines $log 3]. To run it by hand: $manual"
        return
    }
    if {![file exists $out] || ![regexp {script version} [slurp $out]]} {
        path_warn "quartus_sta finished but $out has no report. To run it by hand: $manual"
        return
    }
    path_note "failing paths: $out"
}

# The release comes first and its errors still stop the script, but only after
# the clock report and the path report have had their turn.
set revision [lindex $quartus(args) 2]
set release_failed [catch {release $revision} release_error]
if {[catch {clock_report $revision} report_error]} {
    report_warn "stopped: $report_error"
}
if {[catch {path_report $revision} path_error]} {
    path_warn "stopped: $path_error"
}
if {$release_failed} { error $release_error }
