# Zargs
a non-complete alternative to xargs with advanced templating and less
cli args to bother with. One major difference is that xargs on default
passes all lines from stdin to the provided command and a flag turns
this off so that line wise processing is done... zargs always does
line wise processing...

## Examples

### Append option

The most common usage, where the line from stdin is just appended to
the provided command. **NOTE:** this is line wise processing and it
does not pass all input to the command at once.
```SH
❯ docker ps --format '{{ .ID }}' | zargs docker rm -f
...
```

### Using templating
As there are essentially two columns in the input we can use the templating
syntax to build our commmand.
```SH
❯ ps --no-headers -o pid,exe | zargs echo '{1} using pid {0}'
/usr/bin/bash using pid 7374
/usr/bin/ps using pid 167559
/usr/local/bin/zargs using pid 167560
```

## Usage

```SH
❯ zargs --help
    -h, --help
            Display this help and exit.

    -d, --delimiter <str>
            Column delimiter to use for templating (Defaults to: ' ').

    -s, --tplstart <str>
            What character sequence starts a template placeholder (Defaults to: '{').

    -e, --tplend <str>
            What character sequence ends a template placeholder (Defaults to: '}').

    <str>...
```

### Building

```SH
zig build
```

