regsub -all {<%HM_PIKO_IP%>} $content [string trim $HM_PIKO_IP] content
regsub -all {<%HM_PIKO_USER%>} $content [string trim $HM_PIKO_USER] content
regsub -all {<%HM_PIKO_SECRET%>} $content [string trim $HM_PIKO_SECRET] content
regsub -all {<%HM_CCU_PIKO_VAR%>} $content [string trim $HM_CCU_PIKO_VAR] content
regsub -all {<%HM_INTERVAL_TIME%>} $content [string trim $HM_INTERVAL_TIME] content

puts "Content-Type: text/html; charset=utf-8\n\n"
puts $content
