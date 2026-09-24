#=============================================================================
# File        : cov_summary.awk
# Project     : AXI4 to AHB-Lite Bridge VIP
# Author      : Huy Le
# Description : Summarises a 'vcover report -assert' or '-directive' text
#               report: how many entries carry a non-zero count, and the name
#               of every entry that was never hit.
#               Used by the assert_report target of the Makefile.
#
#               The two reports are laid out differently. An assertion entry
#               puts the name on its own line and the counts on the next:
#                 /bridge_tb_top/axi_checker/B_STABLE
#                                  ../10_tb/sva/axi4_sva.sv(167)    0    5
#               A directive entry may keep the name and the source location on
#               one line and end with a count and a status word:
#                 /bridge_tb_top/ahb_checker/C_WAIT_STATE  ahb_sva ... (343)
#                                                                  0 ZERO
#               So the name is taken from whichever field starts with the
#               instance path, and the count is the last numeric field, or the
#               one before a trailing status word.
#=============================================================================

/^(Errors:|TOTAL|End time|Start time)/ { next }

{
    for (i = 1; i <= NF; i++)
        if ($i ~ /^\/bridge_tb_top\//)
            name = $i
}

name != "" {
    count = ""
    if ($NF ~ /^[0-9]+$/)
        count = $NF
    else if (NF > 1 && $(NF - 1) ~ /^[0-9]+$/)
        count = $(NF - 1)

    if (count != "") {
        total++
        if (count + 0 == 0)
            zero[++zero_count] = name
        else
            hit++
        name = ""
    }
}

END {
    printf "  %d/%d with a non-zero count\n", hit, total
    for (i = 1; i <= zero_count; i++)
        print "    never hit: " zero[i]
}
