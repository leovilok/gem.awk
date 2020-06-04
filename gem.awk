#!/usr/bin/awk -f

# ad hoc, probably very slow URL encoder
function url_encode(url) {
    gsub("%", "%25", url)
    for (i=0 ; i<256 ; i++) {
        char = sprintf("%c",i)
        if (char !~ /[%0-9A-Za-z._~-]/ && index(url, char)) {
            char_re = char ~ /[.^[$()|*+?{\\]/ ? "\\" char : char
            gsub(char_re, sprintf("%%%02X", i), url)
        }
    }
    return url
}

function parse_gemini(connexion_cmd) {
    PAGE_URL=CURRENT_URL
    PAGE_LINE_NUM=0
    PAGE_LINK_NUM=0
    PAGE_TITLE_NUM=0
    pre=0
    for (i in PAGE_LINES) delete PAGE_LINES[i]
    for (i in PAGE_LINKS) delete PAGE_LINKS[i]
    for (i in PAGE_TITLES) delete PAGE_TITLES[i]

    if (!HISTORY_NUM || HISTORY[HISTORY_NUM] != PAGE_URL)
        HISTORY[++HISTORY_NUM] = PAGE_URL

    while (connexion_cmd | getline) {
        if (!pre) {
            if (/^=>/) {
                PAGE_LINKS[++PAGE_LINK_NUM]=length($1) == 2 ? $2 : substr($1, 2)
                match($0, /^=>[ \t]*[^ \t]+[ \t]*/)
                $0="=> [" PAGE_LINK_NUM "] \033[4m" PAGE_LINKS[PAGE_LINK_NUM] "\033[0m " substr($0, RSTART + RLENGTH)
            } else if (/^#/) {
                PAGE_TITLES[++PAGE_TITLE_NUM]=PAGE_LINE_NUM + 1
                $0="\033[1;4m" $0 "\033[0m"
            }
        }

        if (/^```/)
            pre = pre ? 0 : 1
        else
            PAGE_LINES[++PAGE_LINE_NUM]=$0
    }
    close(connexion_cmd)

    for (i in PAGE_LINES)
        print PAGE_LINES[i]
}

function print_text(connexion_cmd) {
    while (connexion_cmd | getline)
        print
    close(connexion_cmd)
}

function connexion_open(url, domain, port) {
    if (!port)
        port = 1965
    connexion_cmd="echo '" url "' | openssl s_client -crlf -quiet -verify_quiet -connect '" domain ":" port "' 2>/dev/null"
    connexion_cmd | getline
}

function plumb_out(connexion_cmd, out) {
	system(connexion_cmd " | tail +2 " out )
}

function gemini_url_open(url) {
    split(url, path_elt, "/")
    domain=path_elt[3]
    port=1965
    if (match(domain, /:[[:digit:]]+$/)) {
        port=substr(domain, RSTART + 1)
        domain=substr(domain, 1, RSTART - 1)
    }

    connexion_open(url, domain, port)

    if (! $0) {
        close(connexion_cmd)
        sub(/null$/, "stdout", connexion_cmd)
        sub(/-quiet -verify_quiet/, "", connexion_cmd)
        print "\033[1mOpenSSL connexion error:\033[0m"
        system(connexion_cmd)
    } else if (/^1./) { # INPUT
        close(connexion_cmd)
        print "Input requested: (blank to ignore)"
        prompt(substr($2, 4, length($2) -4))
        getline
        if ($0)
            gemini_url_open(url "?" url_encode($0))
    } else if (/^2./) { # SUCCESS
        CURRENT_URL=url
        if (!$2 || $2 ~ /text\/gemini/)
            parse_gemini(connexion_cmd)
        else if ($2 ~ /^text/)
            print_text(connexion_cmd)
        else {
            close(connexion_cmd)
            print "Binary filetype: " $2
            print "Blank to ignore, '| cmd' or '> file' to redirect"
            prompt("Redirection ")
            getline
            if (/^[|>]/)
                plumb_out(connexion_cmd, $0)
            else
                print "Ignored."
        }
    } else if (/^3./) { # REDIRECT
        close(connexion_cmd)
        redirect_url = substr($2, 1, length($2) -1)
        print "Follow redirection ? => \033[4m" redirect_url "\033[0m"
        prompt("Y/n")
        getline
        if (! /^[nN]/)
            any_url_open(redirect_url, url)
    } else {
        close(connexion_cmd)
        print "Error: " $0
    }

    # $0 has been completely changed at this point:
    prompt()
    next
}

function any_url_open(url, base_url) {
    if (!base_url)
        base_url = PAGE_URL
    if (url ~ /^[^:]+(\/.*)?$/) {
        # relative link
        if (base_url ~ /\/$/)
            gemini_url_open(base_url url)
        else {
            parent_url=parent(base_url)
            if (parent_url == "gemini://")
                gemini_url_open(base_url "/" url)
            else
                gemini_url_open(parent_url url)
        }
    } else if (url ~ /^gemini:\/\//) {
        gemini_url_open(url)
    } else {
        print "Not a gemini URL, open with (blank to ignore):"
        prompt("System command")
        getline
        if($0)
            system($0 " '" url "'")
    }
}

function parent(url) {
    sub(/\/[^\/]*\/?$/, "/", url)
    return url
}

function prompt(str) {
    printf("%s%s", (str ? str : PAGE_URL), "\033[1m>\033[0m ")
}

function help() {
    print "The following commands are available:"
    print "  gemini://\033[3;4m.*\033[0m : open a gemini URL"
    print "  \033[3;4mn\033[0m           : follow link \033[3;4mn\033[0m of current text/gemini page"
    print "  .           : reload current page"
    print "  ..          : go to parent"
    print "  toc         : list titles in a text/gemini page"
    print "  links       : list URLs linked in a text/gemini page"
    print "  history [\033[3;4mN\033[0m] : list URLs of visited pages, or open \033[3;4mN\033[0mth visited page"
    print "  back        : go back to previous page in history (swapping the 2 last elements of history)"
    print "  help        : show this help"
}

BEGIN {
    help()
    prompt()
}

/^gemini:\/\// {
    gemini_url_open($1)
}

$1 ~ /^[[:digit:]]+$/ {
    if ($1 == 0 || $1 > PAGE_LINK_NUM) {
        print "No link with id " $1
        next
    }
    
    any_url_open(PAGE_LINKS[$1])
}

/^\.$/ {
    if (CURRENT_URL)
        gemini_url_open(CURRENT_URL)
    else
        print "No current page to reload."
}

/^\.\.$/ {
    if (CURRENT_URL) {
        parent_url=parent(CURRENT_URL)
        if (parent_url == "gemini://")
            print "Already at site root."
        else
            gemini_url_open(parent_url)
        }
    else
        print "No current page."
}

$1 == "toc" {
    if (!PAGE_TITLE_NUM) {
        print "No title found."
    }
    for(i in PAGE_TITLES)
        print PAGE_LINES[PAGE_TITLES[i]] ": " PAGE_TITLES[i]
}

$1 == "links" {
    if (!PAGE_LINK_NUM) {
        print "No link found."
    }
    for(i in PAGE_LINKS)
        print "=> [" i "] \033[4m" PAGE_LINKS[i] "\033[0m"
}

$1 == "history" {
    if (!HISTORY_NUM) {
        print "No page visited in this session."
    } else if ($2) {
        if ($2 >= 1 && $2 <= HISTORY_NUM)
            gemini_url_open(HISTORY[$2])
        else
            print "Bad history ID."
    } else
        for(i in HISTORY)
            print "=> [" i "] \033[4m" HISTORY[i] "\033[0m"
}

$1 == "back" {
    if (HISTORY_NUM <= 1) {
        print "Nowhere to go back."
    } else {
        url = HISTORY[HISTORY_NUM - 1]
        HISTORY[HISTORY_NUM - 1] = HISTORY[HISTORY_NUM]
        HISTORY[HISTORY_NUM] = url
        gemini_url_open(url)
    }
}

$1 == "help" {
    help()
}

{ prompt() }

END {
    print "Bye!"
}
