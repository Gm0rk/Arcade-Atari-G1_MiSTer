# ============================================================================
#  Atari G1 for MiSTer
#  release_rbf.tcl -- after a compile: date the core into releases/, and run
#                     the clock report
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
#  Any other revision, such as the debug build, is skipped, as is a revision
#  that defines G1_DEBUG. A compile that fails before the Assembler leaves
#  nothing to release. Failed timing is reported as a warning; the core is
#  still released.
#
#  Clock report. For either revision, when the compile got through the
#  Assembler, it runs tools/clock_report.tcl on the compile's own Timing
#  Analyzer and Fitter reports and writes
#      output_files/<revision>.clock_report.txt
#  The three verdicts (clock rates, timing met, SDRAM I/O constrained) and
#  every failed check go to the Messages window. Where the compile did not
#  finish, or its reports are not this compile's, the file says it was not run
#  instead of keeping an old report. Without tools/clock_report.tcl there is no
#  report. Nothing about the report can stop the release.
# ============================================================================

set production  "Arcade-Atari-G1"
set release_dir "releases"
set report_tcl  "tools/clock_report.tcl"

proc note {msg} { post_message -type info    "release_rbf: $msg" }
proc warn {msg} { post_message -type warning "release_rbf: $msg" }
proc report_note {msg} { post_message -type info    "clock_report: $msg" }
proc report_warn {msg} { post_message -type warning "clock_report: $msg" }

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
    if {[string match "*G1_DEBUG*" $qsf]} {
        warn "$revision.qsf defines G1_DEBUG, so this is a debug core; nothing released"
        return
    }

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

# The release comes first and its errors still stop the script, but only after
# the clock report has had its turn.
set revision [lindex $quartus(args) 2]
set release_failed [catch {release $revision} release_error]
if {[catch {clock_report $revision} report_error]} {
    report_warn "stopped: $report_error"
}
if {$release_failed} { error $release_error }
