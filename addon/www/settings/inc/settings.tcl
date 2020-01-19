set ADDONNAME "hm_kostalpiko"
set FILENAME "/usr/local/addons/hm_kostalpiko/etc/hm_kostalpiko.conf"

array set args { command INV HM_PIKO_IP {} HM_PIKO_USER {} HM_PIKO_SECRET {} HM_CCU_PIKO_VAR {} HM_INTERVAL_TIME {} }

proc utf8 {hex} {
    set hex [string map {% {}} $hex]
    return [encoding convertfrom utf-8 [binary format H* $hex]]
}

proc url-decode str {
    # rewrite "+" back to space
    # protect \ from quoting another '\'
    set str [string map [list + { } "\\" "\\\\" "\[" "\\\["] $str]

    # Replace UTF-8 sequences with calls to the utf8 decode proc...
    regsub -all {(%[0-9A-Fa-f0-9]{2})+} $str {[utf8 \0]} str

    # process \u unicode mapped chars and trim whitespaces
    return [string trim [subst -novar  $str]]
}

proc str-escape str {
    set str [string map -nocase { 
              "\"" "\\\""
              "\$" "\\\$"
              "\\" "\\\\"
              "`"  "\\`"
             } $str]

    return $str
}

proc str-unescape str {
    set str [string map -nocase { 
              "\\\"" "\""
              "\\\$" "\$"
              "\\\\" "\\"
              "\\`"  "`"
             } $str]

    return $str
}


proc parseQuery { } {
    global args env
    
    set query [array names env]
    if { [info exists env(QUERY_STRING)] } {
        set query $env(QUERY_STRING)
    }
    
    foreach item [split $query &] {
        if { [regexp {([^=]+)=(.+)} $item dummy key value] } {
            set args($key) $value
        }
    }
}

proc loadFile { fileName } {
    set content ""
    set fd -1
    
    if { [catch {open $fileName r} fd] } {
        set content ""
    } else {
        set content [read $fd]
        close $fd
    }
    
    return $content
}

proc loadConfigFile { } {
    global FILENAME HM_PIKO_IP HM_PIKO_USER HM_PIKO_SECRET HM_CCU_PIKO_VAR HM_INTERVAL_TIME
    set conf ""
    catch {set conf [loadFile $FILENAME]}

    if { [string trim "$conf"] != "" } {
        set HM_INTERVAL_MAX 0

        regexp -line {^HM_PIKO_IP=\"(.*)\"$} $conf dummy HM_PIKO_IP
        regexp -line {^HM_PIKO_USER=\"(.*)\"$} $conf dummy HM_PIKO_USER
        regexp -line {^HM_PIKO_SECRET=\"(.*)\"$} $conf dummy HM_PIKO_SECRET
        regexp -line {^HM_CCU_PIKO_VAR=\"(.*)\"$} $conf dummy HM_CCU_PIKO_VAR
        regexp -line {^HM_INTERVAL_MAX=\"(.*)\"$} $conf dummy HM_INTERVAL_MAX
        regexp -line {^HM_INTERVAL_TIME=\"(.*)\"$} $conf dummy HM_INTERVAL_TIME

        # if HM_INTERVAL_MAX is 1 we have to uncheck the
        # checkbox to signal that the interval stuff is disabled.
        if { $HM_INTERVAL_MAX == 1 } {
          set HM_INTERVAL_TIME 0
        }

        # make sure to unescape variable content that was properly escaped
        # due to shell variable regulations
        set HM_PIKO_USER [str-unescape $HM_PIKO_USER]
        set HM_PIKO_SECRET [str-unescape $HM_PIKO_SECRET]
    }
}

proc saveConfigFile { } {
    global FILENAME args
        
    set fd [open $FILENAME w]

    set HM_PIKO_IP [url-decode $args(HM_PIKO_IP)]
    set HM_PIKO_USER [url-decode $args(HM_PIKO_USER)]
    set HM_PIKO_SECRET [url-decode $args(HM_PIKO_SECRET)]
    set HM_CCU_PIKO_VAR [url-decode $args(HM_CCU_PIKO_VAR)]
    set HM_INTERVAL_TIME [url-decode $args(HM_INTERVAL_TIME)]

    # make sure to escape variable content that may contain special
    # characters not allowed unescaped in shell variables.
    set HM_PIKO_USER [str-escape $HM_PIKO_USER]
    set HM_PIKO_SECRET [str-escape $HM_PIKO_SECRET]
    
    # we set config options that should not be changeable on the CCU
    puts $fd "HM_CCU_IP=127.0.0.1"
    puts $fd "HM_CCU_REGAPORT=8183"
    puts $fd "HM_PROCESSLOG_FILE=\"/var/log/hm_kostalpiko.log\""
    puts $fd "HM_DAEMON_PIDFILE=\"/var/run/hm_kostalpiko.pid\""

    # only add the following variables if they are NOT empty
    if { [string length $HM_PIKO_IP] > 0 }              { puts $fd "HM_PIKO_IP=\"$HM_PIKO_IP\"" }
    if { [string length $HM_PIKO_USER] > 0 }            { puts $fd "HM_PIKO_USER=\"$HM_PIKO_USER\"" }
    if { [string length $HM_PIKO_SECRET] > 0 }          { puts $fd "HM_PIKO_SECRET=\"$HM_PIKO_SECRET\"" }
    if { [string length $HM_CCU_PIKO_VAR] > 0 }      	{ puts $fd "HM_CCU_PIKO_VAR=\"$HM_CCU_PIKO_VAR\"" }

    if { $HM_INTERVAL_TIME == 0 } { 
      puts $fd "HM_INTERVAL_MAX=\"1\""
    } else {
      puts $fd "HM_INTERVAL_TIME=\"$HM_INTERVAL_TIME\""
    }

    close $fd

    # we have updated our configuration so lets
    # stop/restart hm_kostalpiko
    if { $HM_INTERVAL_TIME == 0 } { 
      exec /usr/local/etc/config/rc.d/hm_kostalpiko stop &
    } else {
      exec /usr/local/etc/config/rc.d/hm_kostalpiko restart &
    }
}
