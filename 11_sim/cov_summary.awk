#=============================================================================
# File        : cov_summary.awk
# Project     : AXI4 to AHB-Lite Bridge VIP
# Author      : Huy Le
# Description : Summarises a 'vcover report -assert' or '-directive' text
#               report: hit count and the names of entries never hit.
#               Name = field starting with the instance path; count = last
#               numeric field (before a trailing status word).
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
