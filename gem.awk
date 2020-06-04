#!/usr/bin/awk -f

function parse_gemini(connexion_cmd) {
    PAGE_URL=CURRENT_URL
    PAGE_LINE_NUM=0
    PAGE_LINK_NUM=0
    PAGE_TITLE_NUM=0
    pre=0
    for (i in PAGE_LINES) delete PAGE_LINES[i]
    for (i in PAGE_LINKS) delete PAGE_LINKS[i]
    for (i in PAGE_TITLES) delete PAGE_TITLES[i]

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

    for (i in PAGE_LINES)
        print PAGE_LINES[i]
}

function print_text(connexion_cmd) {
    while (connexion_cmd | getline)
        print
}

function connexion_open(domain, path, port) {
    if (!port)
        port = 1965
    connexion_cmd="echo 'gemini://" domain "/" path "' | openssl s_client -crlf -quiet -verify_quiet -connect '" domain ":" port "'"
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
    path=url
    sub(/gemini:\/\/[^\/]+\/?/, "", path)

    connexion_open(domain, path, port)

    if (/^2./) {
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
    } else {
        close(connexion_cmd)
        print "Error: " $0
    }
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
    
    url=PAGE_LINKS[$1]
    if (url ~ /^[^:]+(\/.*)?$/) {
        # relative link
        gemini_url_open(PAGE_URL "/" url)
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

/^\.$/ {
    if (CURRENT_URL)
        gemini_url_open(CURRENT_URL)
    else
        print "No current page to reload."
}

/^\.\.$/ {
    if (CURRENT_URL) {
        parent_url=CURRENT_URL
        sub(/\/[^\/]*\/?$/, "/", parent_url)
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
        next
    }
    for(i in PAGE_TITLES)
        print PAGE_LINES[PAGE_TITLES[i]] ": " PAGE_TITLES[i]
}

$1 == "links" {
    if (!PAGE_LINK_NUM) {
        print "No link found."
        next
    }
    for(i in PAGE_LINKS)
        print "=> [" i "] \033[4m" PAGE_LINKS[i] "\033[0m"
}

$1 == "help" {
    help()
}

{ prompt() }

END {
    print "Bye!"
}
