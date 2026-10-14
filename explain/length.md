length: an appcast's enclosure length is the asset's real size.

## Why
The appcast tells the client how big the download is. An appcast generated before the pkg was final
describes a file that no longer exists. The fix is to regenerate the appcast
after the pkg is final.

## Incident
None recorded.

## Limits
It compares the length in the appcast to the size of the file in the dist. A pkg changed after the check
(a re-sign) breaks the match again; the check runs at package time.

## Deviating
Write "- length:<appcast file glob>: <reason>". A good reason says why the length cannot match (a stand-in
feed that describes nothing real), and the exit.

Formerly the conformance rule length
