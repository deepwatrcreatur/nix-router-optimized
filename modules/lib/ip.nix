/**
  Pure-Nix IPv4/IPv6 address and CIDR helpers, used by module assertions
  (subnet overlap, pool-in-subnet checks) and tests.

  Import with `import ./lib/ip.nix { inherit lib; }`.

  Inputs are plain strings such as `"10.0.0.1"`, `"10.0.0.0/24"` or
  `"fd42::1/64"`. A CIDR without a prefix length is treated as a single host
  (`/32` or `/128`).

  # Limitations

  - IPv4 octets must not have leading zeros: `"10.0.0.08"` fails to evaluate.
  - IPv6 addresses with an embedded IPv4 tail (`"::ffff:1.2.3.4"`) are not
    supported and fail to evaluate.
*/
{ lib }:

with lib;

let
  /**
    Parse a decimal string into an integer.

    # GOTCHA

    Uses `builtins.fromJSON`, so a leading zero (`"08"`) is a parse error.
  */
  parseInt = s: builtins.fromJSON s;

  pow2 = n: if n == 0 then 1 else 2 * pow2 (n - 1);

  hexDigits = {
    "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4;
    "5" = 5; "6" = 6; "7" = 7; "8" = 8; "9" = 9;
    "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
    "A" = 10; "B" = 11; "C" = 12; "D" = 13; "E" = 14; "F" = 15;
  };

  hexToInt = s:
    builtins.foldl' (acc: c: acc * 16 + hexDigits.${c}) 0 (lib.stringToCharacters s);

  /**
    Whether an address or CIDR string is IPv6 (contains a `:`).
  */
  isIPv6 = str: hasInfix ":" str;

  /**
    Parse a dotted-quad IPv4 address into a 32-bit integer.
    Asserts four octets in `0..255`.

    # Example

    ```nix
    parseIPv4 "10.0.0.8"
    => 167772168
    ```
  */
  parseIPv4 = ip:
    let
      octets = splitString "." ip;
      parsedOctets = map parseInt octets;
    in
      assert length octets == 4;
      assert all (o: o >= 0 && o <= 255) parsedOctets;
      ((elemAt parsedOctets 0) * 16777216)
      + ((elemAt parsedOctets 1) * 65536)
      + ((elemAt parsedOctets 2) * 256)
      + (elemAt parsedOctets 3);

  /**
    Inverse of `parseIPv4`: format a 32-bit integer as a dotted quad.
  */
  intToIPv4 = intVal:
    let
      o1 = builtins.div intVal 16777216;
      rem1 = intVal - o1 * 16777216;
      o2 = builtins.div rem1 65536;
      rem2 = rem1 - o2 * 65536;
      o3 = builtins.div rem2 256;
      o4 = rem2 - o3 * 256;
    in "${toString o1}.${toString o2}.${toString o3}.${toString o4}";

  /**
    Parse an IPv6 address (with or without `::`) into a list of eight 16-bit
    integers. Does not accept a prefix length or an embedded IPv4 tail.
  */
  parseIPv6Words = ipStr:
    if hasInfix "::" ipStr then
      let
        parts = splitString "::" ipStr;
        leftStr = elemAt parts 0;
        rightStr = elemAt parts 1;
        leftWords = if leftStr == "" then [ ] else map hexToInt (splitString ":" leftStr);
        rightWords = if rightStr == "" then [ ] else map hexToInt (splitString ":" rightStr);
        numMissing = 8 - (length leftWords + length rightWords);
        fillWords = genList (_: 0) numMissing;
      in
        leftWords ++ fillWords ++ rightWords
    else
      map hexToInt (splitString ":" ipStr);

  /**
    Compare two word lists (as returned by `parseIPv6Words`) lexicographically.
    Returns `-1`, `0` or `1`.
  */
  compareWords = a: b:
    if a == [ ] then 0
    else if (head a) < (head b) then -1
    else if (head a) > (head b) then 1
    else compareWords (tail a) (tail b);

  # Mask an 8-word IPv6 address with a prefix length (0..128).
  # Returns { network = [w0..w7]; end = [w0..w7]; }
  maskIPv6 = words: prefixLen:
    let
      genWord = i: isEnd:
        let
          startBit = 16 * i;
          endBit = 16 * (i + 1);
          w = elemAt words i;
        in
          if prefixLen >= endBit then w
          else if prefixLen <= startBit then (if isEnd then 65535 else 0)
          else
            let
              k = prefixLen - startBit;
              step = pow2 (16 - k);
              net = (builtins.div w step) * step;
            in
              if isEnd then net + step - 1 else net;
    in {
      network = genList (i: genWord i false) 8;
      end = genList (i: genWord i true) 8;
    };

  /**
    Parse an IPv4 or IPv6 CIDR. Without a prefix length the CIDR is a single
    host (`/32` or `/128`).

    Returns an attrset with `version`, `ip`, `prefixLen`, `network` and
    either (IPv4) `broadcast`, `ipInt`, `hostCount`, `networkInt`,
    `broadcastInt`, or (IPv6) `end`. IPv4 `network` and `broadcast` are
    strings; IPv6 `network` and `end` are word lists.

    # Example

    ```nix
    (parseCIDR "10.0.0.5/24").network
    => "10.0.0.0"
    ```
  */
  parseCIDR = cidr:
    if isIPv6 cidr then
      let
        parts = splitString "/" cidr;
        ipStr = elemAt parts 0;
        prefixLen = if length parts > 1 then parseInt (elemAt parts 1) else 128;
        rawWords = parseIPv6Words ipStr;
        masked = maskIPv6 rawWords prefixLen;
      in {
        version = 6;
        ip = ipStr;
        inherit prefixLen;
        network = masked.network;
        end = masked.end;
      }
    else
      let
        parts = splitString "/" cidr;
        ipStr = elemAt parts 0;
        prefixLen = if length parts > 1 then parseInt (elemAt parts 1) else 32;
        ipInt = parseIPv4 ipStr;
        hostCount = pow2 (32 - prefixLen);
        networkInt = (builtins.div ipInt hostCount) * hostCount;
        broadcastInt = networkInt + hostCount - 1;
      in {
        version = 4;
        ip = ipStr;
        inherit prefixLen ipInt hostCount networkInt broadcastInt;
        network = intToIPv4 networkInt;
        broadcast = intToIPv4 broadcastInt;
      };

  /**
    Whether two CIDRs share any address. CIDRs of different IP versions never
    overlap.
  */
  cidrsOverlap = cidrA: cidrB:
    let
      pA = parseCIDR cidrA;
      pB = parseCIDR cidrB;
    in
      if pA.version != pB.version then false
      else if pA.version == 4 then
        let
          startMax = if pA.networkInt > pB.networkInt then pA.networkInt else pB.networkInt;
          endMin = if pA.broadcastInt < pB.broadcastInt then pA.broadcastInt else pB.broadcastInt;
        in startMax <= endMin
      else
        (compareWords pA.network pB.end <= 0) && (compareWords pB.network pA.end <= 0);

  /**
    Whether `cidrParent` contains every address of `cidrChild`. A CIDR
    contains itself.

    # Example

    ```nix
    cidrContains "10.0.0.0/8" "10.1.0.0/16"
    => true
    ```
  */
  cidrContains = cidrParent: cidrChild:
    let
      pParent = parseCIDR cidrParent;
      pChild = parseCIDR cidrChild;
    in
      if pParent.version != pChild.version then false
      else if pParent.version == 4 then
        pParent.networkInt <= pChild.networkInt && pParent.broadcastInt >= pChild.broadcastInt
      else
        (compareWords pParent.network pChild.network <= 0) && (compareWords pParent.end pChild.end >= 0);

  /**
    Whether a CIDR contains a single address (given without a prefix length).
  */
  cidrContainsIP = cidr: ip:
    let
      p = parseCIDR cidr;
    in
      if isIPv6 ip then
        if p.version != 6 then false
        else
          let words = parseIPv6Words ip;
          in (compareWords p.network words <= 0) && (compareWords p.end words >= 0)
      else
        if p.version != 4 then false
        else
          let ipInt = parseIPv4 ip;
          in ipInt >= p.networkInt && ipInt <= p.broadcastInt;

  /**
    Strip the prefix length: `"10.0.0.1/24"` becomes `"10.0.0.1"`.
  */
  ipOf = cidrOrIp: head (splitString "/" cidrOrIp);

  /**
    The prefix length as an integer; `32` or `128` when none is given.
  */
  prefixOf = cidrOrIp:
    let parts = splitString "/" cidrOrIp;
    in if length parts > 1 then parseInt (elemAt parts 1) else (if isIPv6 cidrOrIp then 128 else 32);

  /**
    Find every overlapping pair in a list of `{ cidr = "..."; ... }` items.
    Returns a list of `{ a = item; b = item; }`, each pair once, in input order.
    Used by assertions to report conflicting subnets by name.
  */
  findOverlaps = items:
    let
      checkItem = item: rest:
        flatten (map (other:
          if cidrsOverlap item.cidr other.cidr then
            [ { a = item; b = other; } ]
          else
            [ ]
        ) rest);

      loop = list:
        if list == [ ] || length list < 2 then [ ]
        else (checkItem (head list) (tail list)) ++ (loop (tail list));
    in loop items;

in {
  inherit
    isIPv6
    parseInt
    parseIPv4
    intToIPv4
    parseIPv6Words
    compareWords
    parseCIDR
    cidrsOverlap
    cidrContains
    cidrContainsIP
    ipOf
    prefixOf
    findOverlaps;
}
