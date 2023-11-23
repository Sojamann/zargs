## Examples

```SH
❯ ps --no-headers -o pid,exe | zargs echo '{1} using pid {0}'
/usr/bin/bash using pid 7374
/usr/bin/ps using pid 167559
/usr/local/bin/zargs using pid 167560
```

## TODO
- make col range a struct with functions i.e is valid, ...
- make col range allow open ranges
- whats the point of the column cache thingy to store the words and the indecies..
- to use comptime stuff columnStringView could be made to take a variable instead of using MAX_COLUMNS all the time.. which would be a nice practice.

