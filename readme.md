## Examples

```SH
❯ ps --no-headers -o pid,exe | zargs echo '{1} using pid {0}'                    │                             be obtained and the field width permits, or a decimal
/usr/bin/bash using pid 7374                                                                   │                             representation otherwise.
/usr/bin/ps using pid 167559                                                                   │
/usr/local/bin/zargs using pid 167560
```

## TODO
[ ] to use comptime stuff columnStringView could be made to take a variable instead of using MAX_COLUMNS all the time.. which would be a nice practice.
[ ] col ranges i.e. {2-}

