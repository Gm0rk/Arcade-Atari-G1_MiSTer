# ============================================================================
#  Atari G1 for MiSTer
#  release_rbf.tcl -- move the production core into releases/, dated
#
#  Quartus runs this after every compile (POST_FLOW_SCRIPT_FILE in the .qsf),
#  from the project folder. For the production revision only, and only when
#  this compile got through the Assembler, it moves
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
# ============================================================================

set production  "Arcade-Atari-G1"
set release_dir "releases"

proc note {msg} { post_message -type info    "release_rbf: $msg" }
proc warn {msg} { post_message -type warning "release_rbf: $msg" }

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

    set outdir "."
    regexp {(?n)^\s*set_global_assignment\s+-name\s+PROJECT_OUTPUT_DIRECTORY\s+"?([^"\s]+)"?} \
        $qsf -> outdir

    # This compile must have reached the Assembler, and it must have passed:
    # its report is newer than the Fitter's and says Successful.
    set asm "$outdir/$revision.asm.rpt"
    set fit "$outdir/$revision.fit.rpt"
    set rbf "$outdir/$revision.rbf"
    if {![file exists $asm]} {
        note "no Assembler report ($asm); nothing released"
        return
    }
    if {[file exists $fit] && [file mtime $asm] < [file mtime $fit]} {
        note "the Assembler did not run in this compile; nothing released"
        return
    }
    if {![regexp {Assembler Status\s*;\s*Successful} [slurp $asm]]} {
        warn "the Assembler did not succeed; nothing released"
        return
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

release [lindex $quartus(args) 2]
