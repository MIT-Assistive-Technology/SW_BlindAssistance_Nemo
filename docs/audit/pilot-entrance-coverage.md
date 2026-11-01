# Pilot entrance coverage audit (MIT + Kendall)

Source: one Overpass pull of bbox S 42.354, W -71.106, N 42.366, E -71.078 (2026-10-18T20:56:46Z).
Regenerate with `python scripts/audit_entrances.py` from `server/` (add `--fetch` to
re-pull). Rules: docs/car-to-curb-plan.md section 9 (split `;`, exclude
basement, emergency, exit, garage, loading_dock, no, parking; access/foot delivery, no, private).

## Summary

| | Buildings | Share |
|---|---:|---:|
| Building outlines (ways + multipolygons) | 1016 | 100% |
| With at least one usable entrance node | 69 | 6.8% |
| With door nodes, all excluded | 7 | 0.7% |
| With no door-like node at all | 940 | 92.5% |

Named or addressed buildings without a usable entrance: **773**
(MIT, addressed: 113, MIT, no address: 3, Other, named and addressed: 70, Other: 587).

## Buildings to survey

Priority 1 = MIT with an address, 2 = MIT without one, 3 = other named and addressed,
4 = the rest. Status `only_excluded` means the map has doors here but all are exits,
garages, private or similar, so a usable entrance still needs mapping.

| Pri | Name | Address | OSM id | Lat, lon | Status |
|---:|---|---|---|---|---|
| 1 | 11 Homberg Building | 77R Massachusetts Avenue, Cambridge | [way/32517290](https://www.openstreetmap.org/way/32517290) | 42.359503, -71.092724 | none |
| 1 | 17 Wright Brothers Wind Tunnel | 76 Vassar Street, Cambridge | [way/1249521123](https://www.openstreetmap.org/way/1249521123) | 42.360231, -71.093613 | none |
| 1 | 18 Dreyfus Building | 21 Ames Street, Cambridge | [way/24493980](https://www.openstreetmap.org/way/24493980) | 42.360081, -71.089826 | none |
| 1 | 24 | 60 Vassar Street, Cambridge | [way/29127459](https://www.openstreetmap.org/way/29127459) | 42.36066, -71.091973 | none |
| 1 | 26 Compton Labs | 60 Vassar Street, Cambridge | [way/32525936](https://www.openstreetmap.org/way/32525936) | 42.360905, -71.091216 | none |
| 1 | 300 Technology Square | 300 Technology Square, Cambridge | [way/29842810](https://www.openstreetmap.org/way/29842810) | 42.363355, -71.091596 | none |
| 1 | 31 Sloan Labs | 70R Vassar Street, Cambridge | [way/32525033](https://www.openstreetmap.org/way/32525033) | 42.360365, -71.093045 | none |
| 1 | 36 Fairchild Building | 50 Vassar Street, Cambridge | [way/29127425](https://www.openstreetmap.org/way/29127425) | 42.361478, -71.091716 | none |
| 1 | 38 | 50 Vassar Street, Cambridge | [way/32525380](https://www.openstreetmap.org/way/32525380) | 42.361024, -71.092223 | none |
| 1 | 39 Brown Building | 60 Vassar Street, Cambridge | [way/32525350](https://www.openstreetmap.org/way/32525350) | 42.360898, -71.092775 | none |
| 1 | 41 | 77 Vassar Street, Cambridge | [way/29569108](https://www.openstreetmap.org/way/29569108) | 42.360725, -71.094097 | none |
| 1 | 42 Dickson Cogeneration Plant | 59 Vassar Street, Cambridge | [way/132601297](https://www.openstreetmap.org/way/132601297) | 42.361107, -71.093501 | none |
| 1 | 42C | 37 Albany Street, Cambridge | [way/1374253188](https://www.openstreetmap.org/way/1374253188) | 42.361615, -71.093617 | none |
| 1 | 43 Plant Annex | 57 Vassar Street, Cambridge | [way/132601298](https://www.openstreetmap.org/way/132601298) | 42.361245, -71.093356 | none |
| 1 | 45 Schwarzman Building | 51 Vassar Street, Cambridge | [way/1089241940](https://www.openstreetmap.org/way/1089241940) | 42.361671, -71.092387 | none |
| 1 | 46 Brain and Cognitive Sciences | 43 Vassar Street, Cambridge | [relation/17804937](https://www.openstreetmap.org/relation/17804937) | 42.362232, -71.091534 | none |
| 1 | 48 Parsons Lab | 15 Vassar Street, Cambridge | [way/29803755](https://www.openstreetmap.org/way/29803755) | 42.362493, -71.090766 | none |
| 1 | 5 | 55 Massachusetts Avenue, Cambridge | [way/32517556](https://www.openstreetmap.org/way/32517556) | 42.358711, -71.09292 | none |
| 1 | 500 Technology Square | 500 Technology Square, Cambridge | [way/29609886](https://www.openstreetmap.org/way/29609886) | 42.363395, -71.092631 | none |
| 1 | 54 Green Building | 21 Ames Street, Cambridge | [way/24493983](https://www.openstreetmap.org/way/24493983) | 42.360391, -71.089462 | none |
| 1 | 55 | 21 Ames Street, Cambridge | [way/1322990414](https://www.openstreetmap.org/way/1322990414) | 42.360542, -71.089565 | none |
| 1 | 57 Alumni Pool | 6 Vassar Street, Cambridge | [way/32526333](https://www.openstreetmap.org/way/32526333) | 42.361139, -71.090106 | none |
| 1 | 68 Koch Biology Building | 31 Ames Street, Cambridge | [way/1011548273](https://www.openstreetmap.org/way/1011548273) | 42.361636, -71.088639 | only_excluded |
| 1 | 6C | 182R Memorial Drive, Cambridge | [way/32524914](https://www.openstreetmap.org/way/32524914) | 42.359714, -71.090888 | none |
| 1 | 700 Technology Square | 700 Technology Square | [way/29650626](https://www.openstreetmap.org/way/29650626) | 42.364008, -71.092665 | none |
| 1 | 76 Koch Institute | 500 Main Street, Cambridge | [way/46846324](https://www.openstreetmap.org/way/46846324) | 42.362329, -71.089306 | none |
| 1 | 7A Rotch Library | Massachusetts Avenue, Cambridge | [way/435078056](https://www.openstreetmap.org/way/435078056) | 42.359496, -71.093174 | none |
| 1 | Cambridge Riverview Center | 245 First Street, Cambridge | [way/29945511](https://www.openstreetmap.org/way/29945511) | 42.363593, -71.079234 | none |
| 1 | DKE | 403 Memorial Drive, Cambridge | [way/980718780](https://www.openstreetmap.org/way/980718780) | 42.355947, -71.096582 | none |
| 1 | E1 Gray House | 111 Memorial Drive, Cambridge | [way/980722692](https://www.openstreetmap.org/way/980722692) | 42.359558, -71.086877 | none |
| 1 | E17 Mudd Building | 40 Ames Street, Cambridge | [way/220082897](https://www.openstreetmap.org/way/220082897) | 42.361495, -71.087895 | none |
| 1 | E18 Ford Building | 50 Ames Street, Cambridge | [way/220076812](https://www.openstreetmap.org/way/220076812) | 42.361672, -71.08763 | none |
| 1 | E19 | 400 Main Street, Cambridge | [way/220076879](https://www.openstreetmap.org/way/220076879) | 42.36217, -71.087997 | none |
| 1 | E2 70 Amherst | 70 Amherst Street, Cambridge | [way/980722694](https://www.openstreetmap.org/way/980722694) | 42.359989, -71.086902 | none |
| 1 | E28 | 314 Main Street, Cambridge | [way/1254628669](https://www.openstreetmap.org/way/1254628669) | 42.362103, -71.086644 | none |
| 1 | E37 | 45 Hayward Street, Cambridge | [way/1264845022](https://www.openstreetmap.org/way/1264845022) | 42.361895, -71.085472 | none |
| 1 | E38 | 292 Main Street, Cambridge | [way/1264845023](https://www.openstreetmap.org/way/1264845023) | 42.362053, -71.08583 | none |
| 1 | E60 Arthur D. Little Building | 30 Memorial Drive, Cambridge | [way/24494174](https://www.openstreetmap.org/way/24494174) | 42.361117, -71.082067 | none |
| 1 | E62 | 100 Main Street, Cambridge | [way/1047765109](https://www.openstreetmap.org/way/1047765109) | 42.361341, -71.082682 | none |
| 1 | Kappa Sigma | 407 Memorial Drive, Cambridge | [way/980718778](https://www.openstreetmap.org/way/980718778) | 42.356147, -71.097401 | none |
| 1 | MIT Building 1 | 165 Main Street | [way/823968945](https://www.openstreetmap.org/way/823968945) | 42.362641, -71.082791 | none |
| 1 | N10 High Voltage Research Lab | 155 Massachusetts Avenue, Cambridge | [way/29650658](https://www.openstreetmap.org/way/29650658) | 42.360886, -71.095488 | none |
| 1 | N16 Cooling Tower | 60 Albany Street, Cambridge | [way/29559726](https://www.openstreetmap.org/way/29559726) | 42.36122, -71.093942 | none |
| 1 | N16A | 60 Albany Street, Cambridge | [way/1368163871](https://www.openstreetmap.org/way/1368163871) | 42.361192, -71.094308 | none |
| 1 | N20 Ragon Institute | 600 Main Street, Cambridge | [way/1317036718](https://www.openstreetmap.org/way/1317036718) | 42.362458, -71.093125 | none |
| 1 | N4 Albany Garage | 32 Albany Street, Cambridge | [way/29618959](https://www.openstreetmap.org/way/29618959) | 42.362011, -71.092747 | none |
| 1 | N51 | 275 Massachusetts Avenue, Cambridge | [way/132600539](https://www.openstreetmap.org/way/132600539) | 42.362271, -71.097657 | none |
| 1 | N52 | 265 Massachusetts Avenue, Cambridge | [relation/16848651](https://www.openstreetmap.org/relation/16848651) | 42.362258, -71.097179 | none |
| 1 | N9 Superconducting Test Facility | 68 Albany Street, Cambridge | [way/29739496](https://www.openstreetmap.org/way/29739496) | 42.360872, -71.095058 | none |
| 1 | NE49 | 600 Technology Square | [way/29740162](https://www.openstreetmap.org/way/29740162) | 42.363397, -71.093094 | none |
| 1 | NW10 Edgerton House | 143 Albany Street, Cambridge | [relation/17409127](https://www.openstreetmap.org/relation/17409127) | 42.360322, -71.098137 | none |
| 1 | NW12 Nuclear Reactor Lab | 138 Albany Street, Cambridge | [way/132600541](https://www.openstreetmap.org/way/132600541) | 42.360128, -71.096904 | none |
| 1 | NW13 | 144 Albany Street, Cambridge | [way/132600542](https://www.openstreetmap.org/way/132600542) | 42.359868, -71.097331 | none |
| 1 | NW14 Bitter Magnet Lab | 150;166 Albany Street | [way/132600543](https://www.openstreetmap.org/way/132600543) | 42.359659, -71.097941 | none |
| 1 | NW16 | 167 Albany Street, Cambridge | [way/29566343](https://www.openstreetmap.org/way/29566343) | 42.3601, -71.098816 | none |
| 1 | NW17 | 175 Albany Street, Cambridge | [way/132600544](https://www.openstreetmap.org/way/132600544) | 42.359818, -71.099063 | none |
| 1 | NW21 Plasma Science & Fusion Center | 180 Albany Street | [way/29557595](https://www.openstreetmap.org/way/29557595) | 42.359063, -71.099131 | none |
| 1 | NW22 | 185 Albany Street, Cambridge | [way/29708703](https://www.openstreetmap.org/way/29708703) | 42.359748, -71.09962 | none |
| 1 | NW23 | 195 Albany Street, Cambridge | [way/1007111503](https://www.openstreetmap.org/way/1007111503) | 42.35956, -71.099866 | none |
| 1 | NW30 The Warehouse | 224 Albany Street, Cambridge | [way/29929971](https://www.openstreetmap.org/way/29929971) | 42.358662, -71.099982 | none |
| 1 | NW32 | 230 Albany Street, Cambridge | [way/29680531](https://www.openstreetmap.org/way/29680531) | 42.358527, -71.100414 | none |
| 1 | NW35 Ashdown House | 235 Albany Street, Cambridge | [way/29680534](https://www.openstreetmap.org/way/29680534) | 42.358794, -71.101443 | none |
| 1 | NW61 Random Hall | 282 Massachusetts Avenue, Cambridge | [way/29809099](https://www.openstreetmap.org/way/29809099) | 42.361875, -71.098311 | none |
| 1 | NW86 Sidney Pacific | 70 Pacific Street, Cambridge | [way/25679668](https://www.openstreetmap.org/way/25679668) | 42.359761, -71.102247 | none |
| 1 | NW98 | 12 Emily Street, Cambridge | [way/29888553](https://www.openstreetmap.org/way/29888553) | 42.359589, -71.104745 | none |
| 1 | No. 6 | 428 Memorial Drive, Cambridge | [way/29947479](https://www.openstreetmap.org/way/29947479) | 42.355621, -71.098664 | none |
| 1 | Novartis Amenities Building | 250 Massachusetts Avenue, Cambridge | [way/29863763](https://www.openstreetmap.org/way/29863763) | 42.361143, -71.097833 | none |
| 1 | One Broadway | 1 Broadway, Cambridge | [way/141434940](https://www.openstreetmap.org/way/141434940) | 42.362739, -71.083436 | none |
| 1 | Phi Beta Epsilon | 400 Memorial Drive, Cambridge | [way/980718781](https://www.openstreetmap.org/way/980718781) | 42.356414, -71.097045 | none |
| 1 | Pi Beta Phi | 405 Memorial Drive, Cambridge | [way/980718779](https://www.openstreetmap.org/way/980718779) | 42.356183, -71.097216 | none |
| 1 | Riverfront Office Park | 1 Main Street, Cambridge | [way/274265189](https://www.openstreetmap.org/way/274265189) | 42.362225, -71.080023 | none |
| 1 | University Park at MIT Parking Garage | 80 Landsdowne Street, Cambridge | [way/29680415](https://www.openstreetmap.org/way/29680415) | 42.360147, -71.100256 | none |
| 1 | W16 Kresge Auditorium | 48 Massachusetts Avenue | [way/24494029](https://www.openstreetmap.org/way/24494029) | 42.358089, -71.094964 | none |
| 1 | W2 | 311;312 Memorial Drive, Cambridge | [way/29803811](https://www.openstreetmap.org/way/29803811) | 42.35735, -71.093982 | none |
| 1 | W31 du Pont Athletic Gymnasium | 120 Massachusetts Avenue, Cambridge | [way/29127393](https://www.openstreetmap.org/way/29127393) | 42.359648, -71.095205 | none |
| 1 | W32 du Pont Athletic Center | 100 Massachusetts Avenue, Cambridge | [way/132601562](https://www.openstreetmap.org/way/132601562) | 42.359316, -71.095023 | none |
| 1 | W33 Rockwell Cage | 106 Vassar Street, Cambridge | [way/132601563](https://www.openstreetmap.org/way/132601563) | 42.359212, -71.095982 | none |
| 1 | W34 Johnson Athletic Center | 120 Vassar Street, Cambridge | [way/132601564](https://www.openstreetmap.org/way/132601564) | 42.3586, -71.096547 | none |
| 1 | W41 Metropolitan Storage Warehouse | 134 Massachusetts Avenue, Cambridge | [way/29803955](https://www.openstreetmap.org/way/29803955) | 42.359833, -71.096069 | none |
| 1 | W5 Green Hall | 350 Memorial Drive, Cambridge | [way/864631218](https://www.openstreetmap.org/way/864631218) | 42.356768, -71.094842 | none |
| 1 | W51 Burton Conner House | 410 Memorial Drive, Cambridge | [way/980718777](https://www.openstreetmap.org/way/980718777) | 42.355946, -71.098051 | none |
| 1 | W59 Heinz Building | 201 Vassar Street, Cambridge | [way/29681495](https://www.openstreetmap.org/way/29681495) | 42.358105, -71.099528 | none |
| 1 | W61 MacGregor House | 450 Memorial Drive, Cambridge | [way/1246607679](https://www.openstreetmap.org/way/1246607679) | 42.3555, -71.099586 | none |
| 1 | W64 Koch Childcare Center | 219 Vassar Street, Cambridge | [way/29890503](https://www.openstreetmap.org/way/29890503) | 42.357623, -71.100256 | none |
| 1 | W70 New House | 471 Memorial Drive, Cambridge | [way/980619102](https://www.openstreetmap.org/way/980619102) | 42.355148, -71.100477 | none |
| 1 | W79 Simmons Hall | 229 Vassar Street, Cambridge | [way/29585286](https://www.openstreetmap.org/way/29585286) | 42.357092, -71.101481 | none |
| 1 | W8 Resch Boathouse | 409 Memorial Drive, Cambridge | [way/29606898](https://www.openstreetmap.org/way/29606898) | 42.355269, -71.096743 | only_excluded |
| 1 | W83 | 11 Audrey Street, Cambridge | [way/1159673371](https://www.openstreetmap.org/way/1159673371) | 42.355439, -71.104945 | none |
| 1 | W84 Tang Hall | 550 Memorial Drive, Cambridge | [way/29127301](https://www.openstreetmap.org/way/29127301) | 42.354392, -71.103546 | none |
| 1 | W85 Westgate | 540 Memorial Drive, Cambridge | [way/262724455](https://www.openstreetmap.org/way/262724455) | 42.355029, -71.103305 | none |
| 1 | W85ABC | 11;13;15 Audrey Street, Cambridge | [way/29127324](https://www.openstreetmap.org/way/29127324) | 42.354993, -71.103918 | none |
| 1 | W85DE | 290;292 Vassar Street, Cambridge | [way/29127326](https://www.openstreetmap.org/way/29127326) | 42.355393, -71.103972 | none |
| 1 | W85FG | 284;286 Vassar Street, Cambridge | [way/29127349](https://www.openstreetmap.org/way/29127349) | 42.355577, -71.10352 | none |
| 1 | W85HJK | 278;278R;280;282;282R Vassar Street, Cambridge | [way/29127348](https://www.openstreetmap.org/way/29127348) | 42.355374, -71.103017 | none |
| 1 | W87 Grad Junction | 269 Vassar Street, Cambridge | [way/1299334791](https://www.openstreetmap.org/way/1299334791) | 42.356496, -71.102854 | none |
| 1 | W88 Grad Junction | 299 Vassar Street, Cambridge | [way/1299334792](https://www.openstreetmap.org/way/1299334792) | 42.355762, -71.104417 | none |
| 1 | W91 | 565-570 Memorial Drive, Cambridge | [way/29127330](https://www.openstreetmap.org/way/29127330) | 42.354332, -71.10443 | none |
| 1 | W92 Information Technology | 304 Vassar Street, Cambridge | [way/29127327](https://www.openstreetmap.org/way/29127327) | 42.354891, -71.104569 | none |
| 1 | WW25 | 142 Waverly Street, Cambridge | [way/29924888](https://www.openstreetmap.org/way/29924888) | 42.355738, -71.106326 | none |
| 1 | (unnamed) | 1 State Street, Cambridge | [way/29870503](https://www.openstreetmap.org/way/29870503) | 42.362993, -71.09882 | none |
| 1 | (unnamed) | 120 Albany Street, Cambridge | [way/1267448740](https://www.openstreetmap.org/way/1267448740) | 42.359535, -71.095175 | none |
| 1 | (unnamed) | 130 Vassar Street, Cambridge | [way/890880630](https://www.openstreetmap.org/way/890880630) | 42.358666, -71.09749 | none |
| 1 | (unnamed) | 170 Albany Street | [way/29650675](https://www.openstreetmap.org/way/29650675) | 42.359382, -71.098297 | none |
| 1 | (unnamed) | 177;181 Massachusetts Avenue, Cambridge | [way/409937903](https://www.openstreetmap.org/way/409937903) | 42.361431, -71.095923 | none |
| 1 | (unnamed) | 180 Albany Street, Cambridge | [way/132600545](https://www.openstreetmap.org/way/132600545) | 42.359235, -71.098351 | none |
| 1 | (unnamed) | 190 Massachusetts Avenue, Cambridge | [way/29804347](https://www.openstreetmap.org/way/29804347) | 42.361005, -71.096848 | none |
| 1 | (unnamed) | 209;211 Massachusetts Avenue, Cambridge | [way/29860824](https://www.openstreetmap.org/way/29860824) | 42.361651, -71.096651 | none |
| 1 | (unnamed) | 250 Albany Street | [way/1063791901](https://www.openstreetmap.org/way/1063791901) | 42.357547, -71.100788 | none |
| 1 | (unnamed) | 250 Albany Street | [way/1063791902](https://www.openstreetmap.org/way/1063791902) | 42.35783, -71.101546 | none |
| 1 | (unnamed) | 255 Main Street, Cambridge | [way/29944552](https://www.openstreetmap.org/way/29944552) | 42.362704, -71.085283 | none |
| 1 | (unnamed) | 351 Massachusetts Avenue, Cambridge | [way/1098003653](https://www.openstreetmap.org/way/1098003653) | 42.362861, -71.098968 | none |
| 1 | (unnamed) | 355 Main Street, Cambridge | [way/29743556](https://www.openstreetmap.org/way/29743556) | 42.362818, -71.087502 | none |
| 1 | (unnamed) | 410R Memorial Drive, Cambridge | [way/29862811](https://www.openstreetmap.org/way/29862811) | 42.356998, -71.097384 | none |
| 2 | 300 | - | [way/29947888](https://www.openstreetmap.org/way/29947888) | 42.366098, -71.090843 | none |
| 2 | N16C | - | [way/824942622](https://www.openstreetmap.org/way/824942622) | 42.361227, -71.094729 | none |
| 2 | W53 Carr Indoor Tennis | - | [way/29802781](https://www.openstreetmap.org/way/29802781) | 42.356894, -71.097751 | none |
| 3 | 100 Landsdowne | 100 Landsdowne Street, Cambridge | [way/264253041](https://www.openstreetmap.org/way/264253041) | 42.359817, -71.100881 | none |
| 3 | 100 Memorial Drive Apartments | 100 Memorial Drive, Cambridge | [way/1005738154](https://www.openstreetmap.org/way/1005738154) | 42.36023, -71.085816 | none |
| 3 | 100 Technology Square | 100 Technology Square, Cambridge | [way/328256024](https://www.openstreetmap.org/way/328256024) | 42.363412, -71.090506 | none |
| 3 | 200 Broadway | 200 Broadway | [way/835587083](https://www.openstreetmap.org/way/835587083) | 42.365929, -71.093039 | none |
| 3 | 200 Technology Square | 200 Technology Square | [way/328256023](https://www.openstreetmap.org/way/328256023) | 42.363286, -71.091017 | none |
| 3 | 210 Broadway Offices | 210 Broadway, Cambridge | [way/29627050](https://www.openstreetmap.org/way/29627050) | 42.365954, -71.093563 | none |
| 3 | 325 Vassar St | 325 Vassar Street | [way/330070480](https://www.openstreetmap.org/way/330070480) | 42.355027, -71.105823 | none |
| 3 | 400 Technology Square | 400 Technology Square, Cambridge | [way/29575544](https://www.openstreetmap.org/way/29575544) | 42.363991, -71.091972 | none |
| 3 | 500 Kendall Street | 500 Kendall Street, Cambridge | [relation/63754](https://www.openstreetmap.org/relation/63754) | 42.363883, -71.08136 | none |
| 3 | 907 Main | 897;899;901;905;907 Main Street | [way/29513564](https://www.openstreetmap.org/way/29513564) | 42.363696, -71.099621 | none |
| 3 | 91 Sidney | 91 Sidney Street, Cambridge | [way/29579232](https://www.openstreetmap.org/way/29579232) | 42.360746, -71.102378 | none |
| 3 | Aletheia Church | 85 Bishop Allen Drive | [way/29680229](https://www.openstreetmap.org/way/29680229) | 42.365747, -71.10166 | none |
| 3 | American Red Cross | 139 Main Street, Cambridge | [way/29742187](https://www.openstreetmap.org/way/29742187) | 42.362352, -71.082326 | none |
| 3 | Athenæum Press Building | 215 First Street, Cambridge | [way/328678385](https://www.openstreetmap.org/way/328678385) | 42.364304, -71.079265 | none |
| 3 | Barron Building | 616;618;620;622 Massachusetts Avenue | [way/29788695](https://www.openstreetmap.org/way/29788695) | 42.364878, -71.103688 | none |
| 3 | Cambridge Brands | 810 Main Street, Cambridge | [way/29740910](https://www.openstreetmap.org/way/29740910) | 42.362933, -71.097676 | none |
| 3 | Cambridge Center Garage | 73;75;77 Ames Street | [way/58336511](https://www.openstreetmap.org/way/58336511) | 42.3636, -71.088656 | none |
| 3 | Cambridge First Church of the Nazarene | 234 Franklin Street, Cambridge | [way/29630148](https://www.openstreetmap.org/way/29630148) | 42.363768, -71.104349 | none |
| 3 | Cambridge Zen Center | 199 Auburn Street, Cambridge | [way/29924956](https://www.openstreetmap.org/way/29924956) | 42.364363, -71.105985 | none |
| 3 | Central Square Building | 678 Massachusetts Avenue, Cambridge | [way/29794636](https://www.openstreetmap.org/way/29794636) | 42.3655, -71.104419 | none |
| 3 | Charles River Yacht Club | 99 Memorial Drive, Cambridge | [way/813542637](https://www.openstreetmap.org/way/813542637) | 42.359088, -71.084262 | only_excluded |
| 3 | Christian Mission Holiness Church | 789 Main Street, Cambridge | [way/29803324](https://www.openstreetmap.org/way/29803324) | 42.363634, -71.097203 | none |
| 3 | Chroma | 240 Sidney Street | [way/824958047](https://www.openstreetmap.org/way/824958047) | 42.356816, -71.106011 | none |
| 3 | Church Corner Apartments | 10 Magazine Street, Cambridge | [way/29585277](https://www.openstreetmap.org/way/29585277) | 42.364584, -71.104606 | none |
| 3 | Church in Cambridge | 380 Green Street, Cambridge | [way/1236606189](https://www.openstreetmap.org/way/1236606189) | 42.365581, -71.105969 | none |
| 3 | Clark Building | 38 Sidney Street, Cambridge | [way/29681512](https://www.openstreetmap.org/way/29681512) | 42.361446, -71.100738 | none |
| 3 | First Baptist Church | 5 Magazine Street, Cambridge | [way/29825268](https://www.openstreetmap.org/way/29825268) | 42.364772, -71.105024 | none |
| 3 | Frank J. Manning Apartments | 270 Green Street, Cambridge | [way/29935068](https://www.openstreetmap.org/way/29935068) | 42.364294, -71.104225 | none |
| 3 | Gospel Room | 69 Norfolk Street | [way/29791189](https://www.openstreetmap.org/way/29791189) | 42.365844, -71.100826 | none |
| 3 | Green Hall | 11,13 Green Street | [way/29860611](https://www.openstreetmap.org/way/29860611) | 42.361667, -71.098699 | none |
| 3 | Green Street Garage | 260 Green Street, Cambridge | [way/32700365](https://www.openstreetmap.org/way/32700365) | 42.364218, -71.103764 | none |
| 3 | H Mart | 581 Massachusetts Avenue | [way/32608063](https://www.openstreetmap.org/way/32608063) | 42.36527, -71.102278 | none |
| 3 | Hampshire Station | 179;181 Broadway | [way/29951233](https://www.openstreetmap.org/way/29951233) | 42.366638, -71.092807 | none |
| 3 | Jackson Building | 26 Landsdowne Street, Cambridge | [way/29650656](https://www.openstreetmap.org/way/29650656) | 42.360851, -71.098749 | none |
| 3 | Kendall Square Garage | 350 Kendall Street, Cambridge | [way/141434943](https://www.openstreetmap.org/way/141434943) | 42.363419, -71.081916 | only_excluded |
| 3 | Kennedy Biscuit Lofts | 129 Franklin Street, Cambridge | [way/29888833](https://www.openstreetmap.org/way/29888833) | 42.362764, -71.101467 | none |
| 3 | Kennedy Building | 428;434;438;440 Massachusetts Avenue, Cambridge | [way/29828756](https://www.openstreetmap.org/way/29828756) | 42.363383, -71.100896 | none |
| 3 | Loft23 | 23 Sidney Street, Cambridge | [way/45763362](https://www.openstreetmap.org/way/45763362) | 42.362273, -71.100719 | none |
| 3 | Lofts at Kendall Square | 195 Binney Street, Cambridge | [way/29624628](https://www.openstreetmap.org/way/29624628) | 42.366218, -71.083288 | none |
| 3 | Margaret Fuller House | 69;71 Cherry Street | [way/29625894](https://www.openstreetmap.org/way/29625894) | 42.364303, -71.096923 | none |
| 3 | Market Central | 9 Columbia Street, Cambridge | [way/652582445](https://www.openstreetmap.org/way/652582445) | 42.363841, -71.100235 | none |
| 3 | NW36 | 250 Albany Street, Cambridge | [way/863538455](https://www.openstreetmap.org/way/863538455) | 42.358007, -71.101325 | none |
| 3 | Odd Fellows Hall | 534;536;538 Massachusetts Avenue, Cambridge | [way/29828469](https://www.openstreetmap.org/way/29828469) | 42.36414, -71.102148 | none |
| 3 | Pentecostal Tabernacle | 77 Columbia Street, Cambridge | [way/29805656](https://www.openstreetmap.org/way/29805656) | 42.365339, -71.098945 | none |
| 3 | Peter Valentine house | 37 Brookline Street | [way/29941898](https://www.openstreetmap.org/way/29941898) | 42.362942, -71.102827 | none |
| 3 | Pisani Center | 131 Washington Street, Cambridge | [way/29619525](https://www.openstreetmap.org/way/29619525) | 42.364719, -71.094447 | none |
| 3 | Proto | 88 Ames Street, Cambridge | [way/823968926](https://www.openstreetmap.org/way/823968926) | 42.363209, -71.087579 | none |
| 3 | Residence Inn Cambridge | 120 Broadway, Cambridge | [way/29650630](https://www.openstreetmap.org/way/29650630) | 42.363905, -71.08813 | none |
| 3 | Richard N. Merkin Building | 415 Main Street, Cambridge | [way/823968922](https://www.openstreetmap.org/way/823968922) | 42.363032, -71.088736 | none |
| 3 | Rivercourt Condos | 10 Rogers Street | [way/29650608](https://www.openstreetmap.org/way/29650608) | 42.36549, -71.077592 | none |
| 3 | Riverfront Office Park | 101 Main Street, Cambridge | [way/274265187](https://www.openstreetmap.org/way/274265187) | 42.362338, -71.081585 | none |
| 3 | Rowland Research Institute | 100 Land Boulevard, Cambridge | [way/356126853](https://www.openstreetmap.org/way/356126853) | 42.363723, -71.077798 | none |
| 3 | Rush Memorial African Methodist Episcopal Zion Church | 82 School Street, Cambridge | [way/29870267](https://www.openstreetmap.org/way/29870267) | 42.363968, -71.098288 | none |
| 3 | Saint Paul African Methodist Episcopal Church | 31;37 Bishop Allen Drive | [way/29513581](https://www.openstreetmap.org/way/29513581) | 42.364473, -71.099569 | none |
| 3 | Saints Constantine and Helen Church | 14 Magazine Street, Cambridge | [way/29793245](https://www.openstreetmap.org/way/29793245) | 42.364249, -71.105152 | none |
| 3 | Salvation Army Cambridge Corps | 402 Massachusetts Avenue, Cambridge | [way/29795717](https://www.openstreetmap.org/way/29795717) | 42.363152, -71.100536 | none |
| 3 | Savings Bank Building | 689 Massachusetts Avenue | [way/824959631](https://www.openstreetmap.org/way/824959631) | 42.366099, -71.104299 | none |
| 3 | Stanley Building | 75 Ames Street, Cambridge | [way/823968940](https://www.openstreetmap.org/way/823968940) | 42.363491, -71.088418 | none |
| 3 | Station 2 | 378 Massachusetts Avenue, Cambridge | [way/29513583](https://www.openstreetmap.org/way/29513583) | 42.363025, -71.100214 | none |
| 3 | Takeda | 350 Massachusetts Avenue, Cambridge | [way/29708701](https://www.openstreetmap.org/way/29708701) | 42.362471, -71.099602 | none |
| 3 | The Church of Jesus Christ of Latter-day Saints | 65;71 Binney Street | [way/212292201](https://www.openstreetmap.org/way/212292201) | 42.365765, -71.079462 | none |
| 3 | The Holmes Building | Cambridge | [way/29680239](https://www.openstreetmap.org/way/29680239) | 42.36504, -71.103987 | none |
| 3 | The Kendall Hotel | 350 Main Street, Cambridge | [way/29620676](https://www.openstreetmap.org/way/29620676) | 42.362297, -71.087408 | none |
| 3 | U-Haul | 844 Main Street, Cambridge | [way/29574513](https://www.openstreetmap.org/way/29574513) | 42.362998, -71.098543 | none |
| 3 | U.S. Trust Building | 141 Portland Street, Cambridge | [way/835587082](https://www.openstreetmap.org/way/835587082) | 42.365493, -71.092642 | none |
| 3 | Union Baptist Church | 874 Main Street, Cambridge | [way/29869087](https://www.openstreetmap.org/way/29869087) | 42.363085, -71.098838 | none |
| 3 | Vivo Apartments | 270 Third Street, Cambridge | [way/448223350](https://www.openstreetmap.org/way/448223350) | 42.366005, -71.08186 | none |
| 3 | Volpe National Transportation Systems Center | 220 Binney Street, Cambridge | [way/1196985630](https://www.openstreetmap.org/way/1196985630) | 42.365383, -71.085425 | none |
| 3 | Whitehead Institute | 455 Main Street, Cambridge | [way/29650632](https://www.openstreetmap.org/way/29650632) | 42.363464, -71.089408 | none |
| 3 | Zion Pentecostal Tabernacle Church | 5;7 Bishop Allen Drive | [way/29805183](https://www.openstreetmap.org/way/29805183) | 42.363627, -71.098301 | none |
| 4 | Kendall Station | - | [way/29650638](https://www.openstreetmap.org/way/29650638) | 42.363162, -71.080305 | none |
| 4 | Technology Square Garage | - | [way/29607745](https://www.openstreetmap.org/way/29607745) | 42.364775, -71.091965 | none |
| 4 | (unnamed) | 1 Brookline Place | [way/29797354](https://www.openstreetmap.org/way/29797354) | 42.362479, -71.102093 | none |
| 4 | (unnamed) | 1 Cottage Court | [way/29635370](https://www.openstreetmap.org/way/29635370) | 42.361241, -71.104188 | none |
| 4 | (unnamed) | 1 Pine Street | [way/29626706](https://www.openstreetmap.org/way/29626706) | 42.364203, -71.098693 | none |
| 4 | (unnamed) | 10 Cottage Street | [way/29937413](https://www.openstreetmap.org/way/29937413) | 42.362227, -71.10565 | none |
| 4 | (unnamed) | 10 Salem Street | [way/29788960](https://www.openstreetmap.org/way/29788960) | 42.362359, -71.103938 | none |
| 4 | (unnamed) | 10 Suffolk Street | [way/29569928](https://www.openstreetmap.org/way/29569928) | 42.365994, -71.099215 | none |
| 4 | (unnamed) | 10 Watson Street | [way/29920766](https://www.openstreetmap.org/way/29920766) | 42.361874, -71.104209 | none |
| 4 | (unnamed) | 100 Binney Street, Cambridge | [way/589916576](https://www.openstreetmap.org/way/589916576) | 42.365127, -71.080884 | none |
| 4 | (unnamed) | 100 Harvard Street | [way/29623158](https://www.openstreetmap.org/way/29623158) | 42.364746, -71.092994 | none |
| 4 | (unnamed) | 100 Pacific Street | [way/29680400](https://www.openstreetmap.org/way/29680400) | 42.360713, -71.103472 | none |
| 4 | (unnamed) | 100 Pine Street | [way/29808183](https://www.openstreetmap.org/way/29808183) | 42.365708, -71.097546 | none |
| 4 | (unnamed) | 100;102 Auburn Street | [way/29629023](https://www.openstreetmap.org/way/29629023) | 42.362819, -71.104007 | none |
| 4 | (unnamed) | 101 Brookline Street | [way/29820713](https://www.openstreetmap.org/way/29820713) | 42.361356, -71.10398 | none |
| 4 | (unnamed) | 101 Pearl Street | [way/29680321](https://www.openstreetmap.org/way/29680321) | 42.362282, -71.105104 | none |
| 4 | (unnamed) | 101 Washington Street | [way/29742700](https://www.openstreetmap.org/way/29742700) | 42.364426, -71.093698 | none |
| 4 | (unnamed) | 102 Columbia Street | [way/29560590](https://www.openstreetmap.org/way/29560590) | 42.366043, -71.09867 | none |
| 4 | (unnamed) | 103;105 Auburn Street | [way/29821020](https://www.openstreetmap.org/way/29821020) | 42.362535, -71.103033 | none |
| 4 | (unnamed) | 103;105;107;109 School Street | [way/29810191](https://www.openstreetmap.org/way/29810191) | 42.364099, -71.098803 | none |
| 4 | (unnamed) | 104 1/2;104R Pearl Street | [way/212292208](https://www.openstreetmap.org/way/212292208) | 42.362183, -71.105185 | none |
| 4 | (unnamed) | 104;106 Auburn Street | [way/29825471](https://www.openstreetmap.org/way/29825471) | 42.362044, -71.103337 | none |
| 4 | (unnamed) | 104;106 Pine Street | [way/29804640](https://www.openstreetmap.org/way/29804640) | 42.365474, -71.096875 | none |
| 4 | (unnamed) | 105 Brookline Street | [way/29586791](https://www.openstreetmap.org/way/29586791) | 42.361132, -71.103868 | none |
| 4 | (unnamed) | 106;108 Columbia Street | [way/29626267](https://www.openstreetmap.org/way/29626267) | 42.36551, -71.097545 | none |
| 4 | (unnamed) | 106;108 Pearl Street | [way/29680333](https://www.openstreetmap.org/way/29680333) | 42.362564, -71.105977 | none |
| 4 | (unnamed) | 107 Auburn Street | [way/29940561](https://www.openstreetmap.org/way/29940561) | 42.362796, -71.103432 | none |
| 4 | (unnamed) | 107 Columbia Street | [way/29563432](https://www.openstreetmap.org/way/29563432) | 42.366049, -71.098601 | none |
| 4 | (unnamed) | 107 Pearl Street | [way/29829848](https://www.openstreetmap.org/way/29829848) | 42.362911, -71.106703 | none |
| 4 | (unnamed) | 107 Portland Street | [way/29625886](https://www.openstreetmap.org/way/29625886) | 42.364279, -71.093221 | none |
| 4 | (unnamed) | 108 Pine Street | [way/29737573](https://www.openstreetmap.org/way/29737573) | 42.365806, -71.097413 | none |
| 4 | (unnamed) | 108;110 Auburn Street | [way/29787644](https://www.openstreetmap.org/way/29787644) | 42.362652, -71.103784 | none |
| 4 | (unnamed) | 109 Pearl Street | [way/29795078](https://www.openstreetmap.org/way/29795078) | 42.362289, -71.105919 | none |
| 4 | (unnamed) | 109 Pine Street | [way/29555040](https://www.openstreetmap.org/way/29555040) | 42.366161, -71.098158 | none |
| 4 | (unnamed) | 109 Windsor Street | [way/29867666](https://www.openstreetmap.org/way/29867666) | 42.363737, -71.095796 | none |
| 4 | (unnamed) | 10;11 Rollins Court | [way/29580079](https://www.openstreetmap.org/way/29580079) | 42.361034, -71.103211 | none |
| 4 | (unnamed) | 10;12 Lopez Street | [way/29680378](https://www.openstreetmap.org/way/29680378) | 42.361184, -71.104762 | none |
| 4 | (unnamed) | 10;12 Pleasant Street | [way/29889187](https://www.openstreetmap.org/way/29889187) | 42.365693, -71.106036 | none |
| 4 | (unnamed) | 11 Cottage Street | [way/29680310](https://www.openstreetmap.org/way/29680310) | 42.362671, -71.105747 | none |
| 4 | (unnamed) | 11 Magazine Street, Cambridge | [way/29638678](https://www.openstreetmap.org/way/29638678) | 42.364301, -71.105387 | none |
| 4 | (unnamed) | 11 Salem Street, Cambridge | [way/1239475705](https://www.openstreetmap.org/way/1239475705) | 42.362863, -71.104969 | none |
| 4 | (unnamed) | 110 Harvard Street | [way/29714586](https://www.openstreetmap.org/way/29714586) | 42.364705, -71.093168 | none |
| 4 | (unnamed) | 111 Washington Street | [way/29810276](https://www.openstreetmap.org/way/29810276) | 42.364423, -71.093635 | none |
| 4 | (unnamed) | 111;113 Cherry Street | [way/29942352](https://www.openstreetmap.org/way/29942352) | 42.365586, -71.097531 | none |
| 4 | (unnamed) | 112 Pearl Street | [way/29820861](https://www.openstreetmap.org/way/29820861) | 42.362017, -71.105341 | none |
| 4 | (unnamed) | 113 Auburn Street | [way/29829071](https://www.openstreetmap.org/way/29829071) | 42.362725, -71.103283 | none |
| 4 | (unnamed) | 113 Harvard Street | [way/29627492](https://www.openstreetmap.org/way/29627492) | 42.365271, -71.093043 | none |
| 4 | (unnamed) | 113;115 Brookline Street | [way/29633742](https://www.openstreetmap.org/way/29633742) | 42.361436, -71.104883 | none |
| 4 | (unnamed) | 114 Auburn Street | [way/29925490](https://www.openstreetmap.org/way/29925490) | 42.362306, -71.103232 | none |
| 4 | (unnamed) | 114 Pine Street | [way/29650606](https://www.openstreetmap.org/way/29650606) | 42.365913, -71.097369 | none |
| 4 | (unnamed) | 115 Pacific Street | [way/29885969](https://www.openstreetmap.org/way/29885969) | 42.361244, -71.103646 | none |
| 4 | (unnamed) | 115 Pearl Street | [way/29793996](https://www.openstreetmap.org/way/29793996) | 42.361873, -71.105509 | none |
| 4 | (unnamed) | 115;117;119 Harvard Street | [way/29612925](https://www.openstreetmap.org/way/29612925) | 42.365245, -71.093042 | none |
| 4 | (unnamed) | 116,120 Cherry Street | [way/1164182301](https://www.openstreetmap.org/way/1164182301) | 42.365371, -71.096754 | none |
| 4 | (unnamed) | 117 Auburn Street | [way/29923481](https://www.openstreetmap.org/way/29923481) | 42.362815, -71.10342 | none |
| 4 | (unnamed) | 117,119 Pacific Street | [way/29581182](https://www.openstreetmap.org/way/29581182) | 42.361277, -71.103666 | none |
| 4 | (unnamed) | 118,120 Pearl Street | [way/29931361](https://www.openstreetmap.org/way/29931361) | 42.361826, -71.105581 | none |
| 4 | (unnamed) | 119 Auburn Street | [way/29587462](https://www.openstreetmap.org/way/29587462) | 42.362867, -71.103518 | none |
| 4 | (unnamed) | 119 Brookline Street | [way/29926484](https://www.openstreetmap.org/way/29926484) | 42.361371, -71.105056 | none |
| 4 | (unnamed) | 119 Pearl Street | [way/29795032](https://www.openstreetmap.org/way/29795032) | 42.362043, -71.106106 | none |
| 4 | (unnamed) | 119 Windsor Street | [way/29561613](https://www.openstreetmap.org/way/29561613) | 42.364685, -71.096786 | none |
| 4 | (unnamed) | 11;13 Pine Street | [way/29606847](https://www.openstreetmap.org/way/29606847) | 42.364572, -71.098812 | none |
| 4 | (unnamed) | 11;13 Valentine Street, Cambridge | [way/1316974800](https://www.openstreetmap.org/way/1316974800) | 42.360273, -71.105509 | none |
| 4 | (unnamed) | 11;13 Watson Street | [way/29635216](https://www.openstreetmap.org/way/29635216) | 42.362577, -71.104837 | none |
| 4 | (unnamed) | 11;13 William Street | [way/29932877](https://www.openstreetmap.org/way/29932877) | 42.363206, -71.105244 | none |
| 4 | (unnamed) | 11;13;15 Lopez Street | [way/29680365](https://www.openstreetmap.org/way/29680365) | 42.361699, -71.10485 | none |
| 4 | (unnamed) | 11;15 Fiske Place | [way/29681505](https://www.openstreetmap.org/way/29681505) | 42.365583, -71.100097 | none |
| 4 | (unnamed) | 12 Cottage Street | [way/29889441](https://www.openstreetmap.org/way/29889441) | 42.362209, -71.105634 | none |
| 4 | (unnamed) | 12 Douglass Street | [way/29513582](https://www.openstreetmap.org/way/29513582) | 42.364756, -71.101118 | none |
| 4 | (unnamed) | 12 Salem Street | [way/29638207](https://www.openstreetmap.org/way/29638207) | 42.363186, -71.105512 | none |
| 4 | (unnamed) | 12 Suffolk Street | [way/29650598](https://www.openstreetmap.org/way/29650598) | 42.365855, -71.099116 | none |
| 4 | (unnamed) | 12 William Street | [way/29940126](https://www.openstreetmap.org/way/29940126) | 42.362959, -71.105633 | none |
| 4 | (unnamed) | 120 Auburn Street | [way/29926844](https://www.openstreetmap.org/way/29926844) | 42.362913, -71.10421 | none |
| 4 | (unnamed) | 120 Harvard Street | [way/29616645](https://www.openstreetmap.org/way/29616645) | 42.365045, -71.093941 | none |
| 4 | (unnamed) | 120 Pacific Street | [way/29796967](https://www.openstreetmap.org/way/29796967) | 42.360833, -71.103955 | none |
| 4 | (unnamed) | 120A;120B;120C;120D Auburn Street | [way/29634933](https://www.openstreetmap.org/way/29634933) | 42.362926, -71.104744 | none |
| 4 | (unnamed) | 121 Auburn Street | [way/29790758](https://www.openstreetmap.org/way/29790758) | 42.362894, -71.103585 | none |
| 4 | (unnamed) | 121 Washington Street | [way/29604713](https://www.openstreetmap.org/way/29604713) | 42.364427, -71.093879 | none |
| 4 | (unnamed) | 122 Auburn Street | [way/29586449](https://www.openstreetmap.org/way/29586449) | 42.362564, -71.103601 | none |
| 4 | (unnamed) | 123 Cherry Street | [way/29809574](https://www.openstreetmap.org/way/29809574) | 42.365774, -71.097638 | none |
| 4 | (unnamed) | 123;125 Pearl Street | [way/29823327](https://www.openstreetmap.org/way/29823327) | 42.361777, -71.105996 | none |
| 4 | (unnamed) | 124 Pearl Street | [way/29587708](https://www.openstreetmap.org/way/29587708) | 42.361753, -71.105788 | none |
| 4 | (unnamed) | 124;126 Auburn Street | [way/29907177](https://www.openstreetmap.org/way/29907177) | 42.362699, -71.103773 | none |
| 4 | (unnamed) | 125 Broadway, Cambridge | [way/29949702](https://www.openstreetmap.org/way/29949702) | 42.365414, -71.088454 | none |
| 4 | (unnamed) | 125 Brookline Street | [way/1063791910](https://www.openstreetmap.org/way/1063791910) | 42.360988, -71.105052 | none |
| 4 | (unnamed) | 125 Brookline Street | [way/1063791911](https://www.openstreetmap.org/way/1063791911) | 42.361017, -71.104918 | none |
| 4 | (unnamed) | 125 Brookline Street | [way/1063791912](https://www.openstreetmap.org/way/1063791912) | 42.360647, -71.104124 | none |
| 4 | (unnamed) | 125 Brookline Street | [way/1063791913](https://www.openstreetmap.org/way/1063791913) | 42.361069, -71.105185 | none |
| 4 | (unnamed) | 125 Brookline Street | [way/1063791914](https://www.openstreetmap.org/way/1063791914) | 42.361247, -71.105127 | none |
| 4 | (unnamed) | 125 Brookline Street | [way/1063791919](https://www.openstreetmap.org/way/1063791919) | 42.361136, -71.105111 | none |
| 4 | (unnamed) | 125 Harvard Street | [way/29949829](https://www.openstreetmap.org/way/29949829) | 42.365436, -71.093238 | none |
| 4 | (unnamed) | 125 Portland Street, Cambridge | [way/835587084](https://www.openstreetmap.org/way/835587084) | 42.365187, -71.092572 | none |
| 4 | (unnamed) | 125 Sidney Street | [way/29888516](https://www.openstreetmap.org/way/29888516) | 42.359844, -71.103711 | none |
| 4 | (unnamed) | 125;127 Cherry Street | [way/29608673](https://www.openstreetmap.org/way/29608673) | 42.36502, -71.096085 | none |
| 4 | (unnamed) | 126;128 Pearl Street | [way/29827109](https://www.openstreetmap.org/way/29827109) | 42.361887, -71.106245 | none |
| 4 | (unnamed) | 128 Cherry Street | [way/29623119](https://www.openstreetmap.org/way/29623119) | 42.365302, -71.09636 | none |
| 4 | (unnamed) | 128;146 Sidney Street | [way/29789115](https://www.openstreetmap.org/way/29789115) | 42.359254, -71.103119 | none |
| 4 | (unnamed) | 129 Auburn Street | [way/29794851](https://www.openstreetmap.org/way/29794851) | 42.362795, -71.103433 | none |
| 4 | (unnamed) | 12;14 Valentine Street | [way/29922038](https://www.openstreetmap.org/way/29922038) | 42.36022, -71.106055 | none |
| 4 | (unnamed) | 12;14;16;18 Fiske Place | [way/29787191](https://www.openstreetmap.org/way/29787191) | 42.365506, -71.100021 | none |
| 4 | (unnamed) | 12A Watson Street | [way/29680349](https://www.openstreetmap.org/way/29680349) | 42.361783, -71.104357 | none |
| 4 | (unnamed) | 12B Watson Street | [way/1193584330](https://www.openstreetmap.org/way/1193584330) | 42.362061, -71.104961 | none |
| 4 | (unnamed) | 13 Cottage Street | [way/29821317](https://www.openstreetmap.org/way/29821317) | 42.36324, -71.106699 | none |
| 4 | (unnamed) | 13 Decatur Street | [way/29793851](https://www.openstreetmap.org/way/29793851) | 42.360697, -71.104505 | none |
| 4 | (unnamed) | 13 Magazine Street, Cambridge | [way/29578174](https://www.openstreetmap.org/way/29578174) | 42.364165, -71.105369 | none |
| 4 | (unnamed) | 13,15 Douglass Street | [way/1232557554](https://www.openstreetmap.org/way/1232557554) | 42.364926, -71.101375 | none |
| 4 | (unnamed) | 130 Harvard Street | [way/29650605](https://www.openstreetmap.org/way/29650605) | 42.365198, -71.094134 | none |
| 4 | (unnamed) | 130 Waverly Street, Cambridge | [way/29829688](https://www.openstreetmap.org/way/29829688) | 42.357084, -71.104797 | none |
| 4 | (unnamed) | 131 Auburn Street | [way/29633626](https://www.openstreetmap.org/way/29633626) | 42.363054, -71.103889 | none |
| 4 | (unnamed) | 131 Harvard Street | [way/823976050](https://www.openstreetmap.org/way/823976050) | 42.365518, -71.093747 | none |
| 4 | (unnamed) | 132 Cherry Street | [way/29842715](https://www.openstreetmap.org/way/29842715) | 42.365308, -71.09617 | none |
| 4 | (unnamed) | 132 Pearl Street | [way/29591548](https://www.openstreetmap.org/way/29591548) | 42.361847, -71.106447 | none |
| 4 | (unnamed) | 137 Cherry Street | [way/29560623](https://www.openstreetmap.org/way/29560623) | 42.365907, -71.097248 | none |
| 4 | (unnamed) | 138 Cherry Street | [way/1240145493](https://www.openstreetmap.org/way/1240145493) | 42.366322, -71.097632 | none |
| 4 | (unnamed) | 13;15 Cherry Street | [way/29740905](https://www.openstreetmap.org/way/29740905) | 42.363612, -71.0976 | none |
| 4 | (unnamed) | 14 Lopez Street | [way/29825087](https://www.openstreetmap.org/way/29825087) | 42.361372, -71.104819 | none |
| 4 | (unnamed) | 14 Merriam Street | [way/652167463](https://www.openstreetmap.org/way/652167463) | 42.358071, -71.103624 | none |
| 4 | (unnamed) | 14 Salem Street | [way/29932782](https://www.openstreetmap.org/way/29932782) | 42.362459, -71.104503 | none |
| 4 | (unnamed) | 14 Watson Street | [way/212292711](https://www.openstreetmap.org/way/212292711) | 42.361701, -71.104346 | none |
| 4 | (unnamed) | 14 William Street | [way/29941785](https://www.openstreetmap.org/way/29941785) | 42.362894, -71.105486 | none |
| 4 | (unnamed) | 140 Harvard Street | [way/29868913](https://www.openstreetmap.org/way/29868913) | 42.365477, -71.094837 | none |
| 4 | (unnamed) | 140;142;144 Pearl Street | [way/29904045](https://www.openstreetmap.org/way/29904045) | 42.361202, -71.106226 | none |
| 4 | (unnamed) | 141 Washington Street | [way/29743462](https://www.openstreetmap.org/way/29743462) | 42.364924, -71.094934 | none |
| 4 | (unnamed) | 142 Cherry Street | [way/1240145492](https://www.openstreetmap.org/way/1240145492) | 42.365615, -71.096313 | none |
| 4 | (unnamed) | 145 Broadway | [way/29864502](https://www.openstreetmap.org/way/29864502) | 42.364918, -71.088717 | none |
| 4 | (unnamed) | 146,148 Cherry Street | [way/1240145491](https://www.openstreetmap.org/way/1240145491) | 42.366139, -71.097064 | none |
| 4 | (unnamed) | 148 Sidney Street, Cambridge | [way/29905744](https://www.openstreetmap.org/way/29905744) | 42.358836, -71.103809 | none |
| 4 | (unnamed) | 149 Auburn Street | [way/29924453](https://www.openstreetmap.org/way/29924453) | 42.363256, -71.104171 | none |
| 4 | (unnamed) | 149 Sidney Street, Cambridge | [way/328480676](https://www.openstreetmap.org/way/328480676) | 42.359303, -71.104211 | none |
| 4 | (unnamed) | 149,151 Cherry Street | [way/29805288](https://www.openstreetmap.org/way/29805288) | 42.366021, -71.096981 | none |
| 4 | (unnamed) | 149;151 Windsor Street | [way/29650613](https://www.openstreetmap.org/way/29650613) | 42.364962, -71.096079 | none |
| 4 | (unnamed) | 15 Cottage Street | [way/29633462](https://www.openstreetmap.org/way/29633462) | 42.362882, -71.106097 | none |
| 4 | (unnamed) | 15 Magazine Street, Cambridge | [way/1206008567](https://www.openstreetmap.org/way/1206008567) | 42.363736, -71.104761 | none |
| 4 | (unnamed) | 15 Valentine Street | [way/212292307](https://www.openstreetmap.org/way/212292307) | 42.360884, -71.105445 | none |
| 4 | (unnamed) | 15 Valentine Street | [way/212292440](https://www.openstreetmap.org/way/212292440) | 42.360557, -71.105965 | none |
| 4 | (unnamed) | 15 Valentine Street | [way/712133778](https://www.openstreetmap.org/way/712133778) | 42.361456, -71.107114 | none |
| 4 | (unnamed) | 15 Valentine Street | [way/712133779](https://www.openstreetmap.org/way/712133779) | 42.360016, -71.104341 | none |
| 4 | (unnamed) | 15 Valentine Street | [way/1316974804](https://www.openstreetmap.org/way/1316974804) | 42.360754, -71.105376 | none |
| 4 | (unnamed) | 15 Watson Street | [way/29927463](https://www.openstreetmap.org/way/29927463) | 42.361346, -71.102831 | none |
| 4 | (unnamed) | 15 William Street | [way/29929516](https://www.openstreetmap.org/way/29929516) | 42.363583, -71.105889 | none |
| 4 | (unnamed) | 15,15.5,17,17.5 Bishop Allen Drive, Cambridge | [way/1161455925](https://www.openstreetmap.org/way/1161455925) | 42.363699, -71.098378 | none |
| 4 | (unnamed) | 150 Broadway, Cambridge | [way/29804416](https://www.openstreetmap.org/way/29804416) | 42.364327, -71.089053 | none |
| 4 | (unnamed) | 150 Harvard Street | [way/29804803](https://www.openstreetmap.org/way/29804803) | 42.365654, -71.095069 | none |
| 4 | (unnamed) | 151 Auburn Street, Cambridge | [way/29939248](https://www.openstreetmap.org/way/29939248) | 42.364353, -71.106069 | none |
| 4 | (unnamed) | 151 Washington Street | [way/29743496](https://www.openstreetmap.org/way/29743496) | 42.364782, -71.095073 | none |
| 4 | (unnamed) | 151R;153;155;155B Cherry Street | [way/29615584](https://www.openstreetmap.org/way/29615584) | 42.365707, -71.096477 | none |
| 4 | (unnamed) | 152;154 Brookline Street | [way/29680447](https://www.openstreetmap.org/way/29680447) | 42.359793, -71.104683 | none |
| 4 | (unnamed) | 153 Auburn Street, Cambridge | [way/1206008568](https://www.openstreetmap.org/way/1206008568) | 42.36345, -71.104552 | none |
| 4 | (unnamed) | 154 Cherry Street | [way/1240145496](https://www.openstreetmap.org/way/1240145496) | 42.365277, -71.095401 | none |
| 4 | (unnamed) | 154;156 Auburn Street | [way/29887743](https://www.openstreetmap.org/way/29887743) | 42.363237, -71.104843 | none |
| 4 | (unnamed) | 155 Brookline Street | [way/1316974803](https://www.openstreetmap.org/way/1316974803) | 42.360315, -71.105505 | none |
| 4 | (unnamed) | 155 Brookline Street, Cambridge | [relation/13334236](https://www.openstreetmap.org/relation/13334236) | 42.360492, -71.105062 | none |
| 4 | (unnamed) | 155;157 Windsor Street | [way/29621173](https://www.openstreetmap.org/way/29621173) | 42.365416, -71.096602 | none |
| 4 | (unnamed) | 156 Cherry Street | [way/1240145495](https://www.openstreetmap.org/way/1240145495) | 42.365748, -71.096059 | none |
| 4 | (unnamed) | 156;158 Brookline Street | [way/29821895](https://www.openstreetmap.org/way/29821895) | 42.359619, -71.104567 | none |
| 4 | (unnamed) | 156R Auburn Street | [way/29905757](https://www.openstreetmap.org/way/29905757) | 42.363174, -71.104983 | none |
| 4 | (unnamed) | 157 Auburn Street | [way/29820569](https://www.openstreetmap.org/way/29820569) | 42.363692, -71.104833 | none |
| 4 | (unnamed) | 158 Auburn Street | [way/29886128](https://www.openstreetmap.org/way/29886128) | 42.363129, -71.104584 | none |
| 4 | (unnamed) | 158;160 Sidney Street | [way/29629531](https://www.openstreetmap.org/way/29629531) | 42.358559, -71.104146 | none |
| 4 | (unnamed) | 159 Windsor Street | [way/29614804](https://www.openstreetmap.org/way/29614804) | 42.36544, -71.096589 | none |
| 4 | (unnamed) | 15;17;19;21 Pine Street | [way/29650620](https://www.openstreetmap.org/way/29650620) | 42.364184, -71.098294 | none |
| 4 | (unnamed) | 16 Watson Street | [way/29680341](https://www.openstreetmap.org/way/29680341) | 42.361771, -71.104026 | none |
| 4 | (unnamed) | 16,18 Salem Street, Cambridge | [way/1365555302](https://www.openstreetmap.org/way/1365555302) | 42.362304, -71.104346 | none |
| 4 | (unnamed) | 160 Harvard Street | [way/29807692](https://www.openstreetmap.org/way/29807692) | 42.365939, -71.095547 | none |
| 4 | (unnamed) | 160;162 Brookline Street | [way/29940221](https://www.openstreetmap.org/way/29940221) | 42.35976, -71.104982 | none |
| 4 | (unnamed) | 161 First Street | [way/29864140](https://www.openstreetmap.org/way/29864140) | 42.365605, -71.078379 | none |
| 4 | (unnamed) | 161 Windsor Street | [way/29738233](https://www.openstreetmap.org/way/29738233) | 42.36589, -71.097173 | none |
| 4 | (unnamed) | 161;163 Auburn Street | [way/29940266](https://www.openstreetmap.org/way/29940266) | 42.363659, -71.104858 | none |
| 4 | (unnamed) | 161;172;174;176 Washington Street | [way/29552431](https://www.openstreetmap.org/way/29552431) | 42.36488, -71.095312 | none |
| 4 | (unnamed) | 162 Sidney Street | [way/29886742](https://www.openstreetmap.org/way/29886742) | 42.358961, -71.105069 | none |
| 4 | (unnamed) | 163 Brookline Street | [way/29581454](https://www.openstreetmap.org/way/29581454) | 42.359727, -71.105093 | none |
| 4 | (unnamed) | 164 Auburn Street | [way/29888959](https://www.openstreetmap.org/way/29888959) | 42.363305, -71.104912 | none |
| 4 | (unnamed) | 164;166 Brookline Street | [way/29926302](https://www.openstreetmap.org/way/29926302) | 42.359493, -71.104719 | none |
| 4 | (unnamed) | 165 Auburn Street, Cambridge | [way/1159751484](https://www.openstreetmap.org/way/1159751484) | 42.363668, -71.104645 | none |
| 4 | (unnamed) | 165,167,169 Brookline Street | [way/1193584331](https://www.openstreetmap.org/way/1193584331) | 42.359832, -71.105581 | none |
| 4 | (unnamed) | 166 Auburn Street | [way/29828060](https://www.openstreetmap.org/way/29828060) | 42.363534, -71.105302 | none |
| 4 | (unnamed) | 167 Sidney Street, Cambridge | [way/328481023](https://www.openstreetmap.org/way/328481023) | 42.358779, -71.104818 | none |
| 4 | (unnamed) | 167 Windsor Street | [way/29716871](https://www.openstreetmap.org/way/29716871) | 42.36514, -71.095715 | none |
| 4 | (unnamed) | 167;169 Auburn Street | [way/29789671](https://www.openstreetmap.org/way/29789671) | 42.363643, -71.104842 | none |
| 4 | (unnamed) | 168 Brookline Street | [way/29680463](https://www.openstreetmap.org/way/29680463) | 42.359866, -71.105487 | none |
| 4 | (unnamed) | 169;171 Windsor Street | [way/29606734](https://www.openstreetmap.org/way/29606734) | 42.365636, -71.096392 | none |
| 4 | (unnamed) | 16;18 Cherry Street | [way/29619608](https://www.openstreetmap.org/way/29619608) | 42.363751, -71.097444 | none |
| 4 | (unnamed) | 16;18 Pine Street | [way/29625064](https://www.openstreetmap.org/way/29625064) | 42.364666, -71.098839 | none |
| 4 | (unnamed) | 16;18 Suffolk Street | [way/29681501](https://www.openstreetmap.org/way/29681501) | 42.365963, -71.099359 | none |
| 4 | (unnamed) | 16;18 Valentine Street | [way/29922358](https://www.openstreetmap.org/way/29922358) | 42.359983, -71.105641 | none |
| 4 | (unnamed) | 16;18 William Street | [way/29788413](https://www.openstreetmap.org/way/29788413) | 42.362893, -71.105455 | none |
| 4 | (unnamed) | 17 Magazine Street, Cambridge | [way/1206008566](https://www.openstreetmap.org/way/1206008566) | 42.36428, -71.105785 | none |
| 4 | (unnamed) | 17 William Street | [way/29824020](https://www.openstreetmap.org/way/29824020) | 42.363675, -71.106031 | none |
| 4 | (unnamed) | 170 Brookline Street | [way/29680470](https://www.openstreetmap.org/way/29680470) | 42.359753, -71.105452 | none |
| 4 | (unnamed) | 170 Brookline Street | [way/29930916](https://www.openstreetmap.org/way/29930916) | 42.359746, -71.105473 | none |
| 4 | (unnamed) | 170 Windsor Street | [way/29946111](https://www.openstreetmap.org/way/29946111) | 42.36501, -71.095909 | none |
| 4 | (unnamed) | 171 Brookline Street | [way/29786099](https://www.openstreetmap.org/way/29786099) | 42.359569, -71.105426 | none |
| 4 | (unnamed) | 172 Brookline Street | [way/29936105](https://www.openstreetmap.org/way/29936105) | 42.359565, -71.105327 | none |
| 4 | (unnamed) | 172 Franklin Street | [way/652081726](https://www.openstreetmap.org/way/652081726) | 42.362188, -71.101552 | none |
| 4 | (unnamed) | 172;174 Auburn Street | [way/29792269](https://www.openstreetmap.org/way/29792269) | 42.363651, -71.105523 | none |
| 4 | (unnamed) | 173 Auburn Street | [way/29576702](https://www.openstreetmap.org/way/29576702) | 42.363859, -71.105095 | none |
| 4 | (unnamed) | 174;176 Brookline Street | [way/29902930](https://www.openstreetmap.org/way/29902930) | 42.3596, -71.105583 | none |
| 4 | (unnamed) | 174;176 Franklin Street | [way/652081713](https://www.openstreetmap.org/way/652081713) | 42.362958, -71.103112 | none |
| 4 | (unnamed) | 175;179 Brookline Street | [way/29680464](https://www.openstreetmap.org/way/29680464) | 42.359635, -71.106035 | none |
| 4 | (unnamed) | 177 Franklin Street | [way/212292504](https://www.openstreetmap.org/way/212292504) | 42.362989, -71.102336 | none |
| 4 | (unnamed) | 177 Windsor Street | [way/29650602](https://www.openstreetmap.org/way/29650602) | 42.366064, -71.096845 | none |
| 4 | (unnamed) | 178;180 Franklin Street | [way/652081714](https://www.openstreetmap.org/way/652081714) | 42.363156, -71.103174 | none |
| 4 | (unnamed) | 179 Sidney Street, Cambridge | [way/29902785](https://www.openstreetmap.org/way/29902785) | 42.358487, -71.105344 | none |
| 4 | (unnamed) | 17;19 Decatur Street | [way/29680374](https://www.openstreetmap.org/way/29680374) | 42.361408, -71.105751 | none |
| 4 | (unnamed) | 17;25 Tudor Street | [way/29796899](https://www.openstreetmap.org/way/29796899) | 42.360058, -71.103957 | none |
| 4 | (unnamed) | 18 Lopez Street | [way/29822540](https://www.openstreetmap.org/way/29822540) | 42.361019, -71.104257 | none |
| 4 | (unnamed) | 180 Windsor Street | [way/29604764](https://www.openstreetmap.org/way/29604764) | 42.365755, -71.096187 | none |
| 4 | (unnamed) | 181 Windsor Street | [way/29863679](https://www.openstreetmap.org/way/29863679) | 42.365734, -71.096062 | none |
| 4 | (unnamed) | 182 Binney Street | [way/29650610](https://www.openstreetmap.org/way/29650610) | 42.3654, -71.083537 | none |
| 4 | (unnamed) | 183 Franklin Street | [way/29791614](https://www.openstreetmap.org/way/29791614) | 42.363447, -71.103052 | none |
| 4 | (unnamed) | 184 Green Street | [way/29590696](https://www.openstreetmap.org/way/29590696) | 42.363619, -71.102554 | none |
| 4 | (unnamed) | 185 Broadway | [way/29866161](https://www.openstreetmap.org/way/29866161) | 42.365975, -71.091783 | none |
| 4 | (unnamed) | 186 Brookline Street | [way/29938116](https://www.openstreetmap.org/way/29938116) | 42.359188, -71.105448 | none |
| 4 | (unnamed) | 187 Brookline Street | [way/29632024](https://www.openstreetmap.org/way/29632024) | 42.359913, -71.106802 | none |
| 4 | (unnamed) | 187,189 Windsor Street | [way/29719567](https://www.openstreetmap.org/way/29719567) | 42.365702, -71.095749 | none |
| 4 | (unnamed) | 188 Auburn Street, Cambridge | [way/29902370](https://www.openstreetmap.org/way/29902370) | 42.363631, -71.105386 | none |
| 4 | (unnamed) | 188 Franklin Street | [way/29822074](https://www.openstreetmap.org/way/29822074) | 42.362674, -71.102412 | none |
| 4 | (unnamed) | 188;190 Brookline Street | [way/29680500](https://www.openstreetmap.org/way/29680500) | 42.359204, -71.105715 | none |
| 4 | (unnamed) | 188;190;192;194 Green Street | [way/29824268](https://www.openstreetmap.org/way/29824268) | 42.363379, -71.102166 | none |
| 4 | (unnamed) | 18;20 Watson Street | [way/29587447](https://www.openstreetmap.org/way/29587447) | 42.362342, -71.104991 | none |
| 4 | (unnamed) | 19 Bishop Allen Drive | [way/1161455924](https://www.openstreetmap.org/way/1161455924) | 42.363497, -71.098068 | none |
| 4 | (unnamed) | 19 Brookline Street | [way/1159718850](https://www.openstreetmap.org/way/1159718850) | 42.363628, -71.101808 | none |
| 4 | (unnamed) | 19 Magazine Street, Cambridge | [way/1206008565](https://www.openstreetmap.org/way/1206008565) | 42.364559, -71.106365 | none |
| 4 | (unnamed) | 19,21,23,25 Watson Street | [way/29891271](https://www.openstreetmap.org/way/29891271) | 42.362049, -71.104025 | none |
| 4 | (unnamed) | 191 Franklin Street | [way/29924977](https://www.openstreetmap.org/way/29924977) | 42.363005, -71.102411 | none |
| 4 | (unnamed) | 192 Franklin Street | [way/29796517](https://www.openstreetmap.org/way/29796517) | 42.363694, -71.104461 | none |
| 4 | (unnamed) | 193;195 Franklin Street | [way/29922913](https://www.openstreetmap.org/way/29922913) | 42.363678, -71.103183 | none |
| 4 | (unnamed) | 194 Franklin Street | [way/29586510](https://www.openstreetmap.org/way/29586510) | 42.363381, -71.103612 | none |
| 4 | (unnamed) | 195;197 Green Street | [way/29585120](https://www.openstreetmap.org/way/29585120) | 42.364103, -71.102635 | none |
| 4 | (unnamed) | 196;198 Broadway, Cambridge | [way/835587080](https://www.openstreetmap.org/way/835587080) | 42.36575, -71.092536 | none |
| 4 | (unnamed) | 196;198 Franklin Street | [way/29629453](https://www.openstreetmap.org/way/29629453) | 42.363014, -71.102969 | none |
| 4 | (unnamed) | 196;198;200 Green Street | [way/29905947](https://www.openstreetmap.org/way/29905947) | 42.363736, -71.102772 | none |
| 4 | (unnamed) | 197 Franklin Street | [way/29578745](https://www.openstreetmap.org/way/29578745) | 42.363271, -71.102846 | none |
| 4 | (unnamed) | 199;201 Franklin Street | [way/29922717](https://www.openstreetmap.org/way/29922717) | 42.363683, -71.103257 | none |
| 4 | (unnamed) | 1;2;3 Glenn Terrace | [way/29579068](https://www.openstreetmap.org/way/29579068) | 42.359461, -71.105411 | none |
| 4 | (unnamed) | 1;2;3;4;5;6 Rollins Court | [way/29577756](https://www.openstreetmap.org/way/29577756) | 42.361636, -71.104652 | none |
| 4 | (unnamed) | 1;3 Salem Street | [way/29940422](https://www.openstreetmap.org/way/29940422) | 42.362729, -71.103979 | none |
| 4 | (unnamed) | 1;3;5;7;9 Newtowne Court | [way/29556300](https://www.openstreetmap.org/way/29556300) | 42.363549, -71.096234 | none |
| 4 | (unnamed) | 2 Cherry Court | [way/29611520](https://www.openstreetmap.org/way/29611520) | 42.364225, -71.097021 | none |
| 4 | (unnamed) | 2 Cottage Court | [way/29579940](https://www.openstreetmap.org/way/29579940) | 42.361475, -71.104623 | none |
| 4 | (unnamed) | 2 William Street | [way/1279412415](https://www.openstreetmap.org/way/1279412415) | 42.363041, -71.105645 | none |
| 4 | (unnamed) | 20 Decatur Street | [way/212292904](https://www.openstreetmap.org/way/212292904) | 42.361287, -71.106417 | none |
| 4 | (unnamed) | 200 Sidney Street, Cambridge | [way/29884496](https://www.openstreetmap.org/way/29884496) | 42.357765, -71.104959 | none |
| 4 | (unnamed) | 200-202 Beacon Street, Boston | [way/405331309](https://www.openstreetmap.org/way/405331309) | 42.354245, -71.077845 | none |
| 4 | (unnamed) | 200;202;204;206 Franklin Street | [way/29924830](https://www.openstreetmap.org/way/29924830) | 42.363376, -71.103588 | none |
| 4 | (unnamed) | 201 Broadway, Cambridge | [way/29573948](https://www.openstreetmap.org/way/29573948) | 42.36625, -71.092366 | none |
| 4 | (unnamed) | 202 Green Street | [way/212292186](https://www.openstreetmap.org/way/212292186) | 42.363735, -71.102786 | none |
| 4 | (unnamed) | 202;204 Sidney Street | [way/29629118](https://www.openstreetmap.org/way/29629118) | 42.357646, -71.105475 | none |
| 4 | (unnamed) | 203 Franklin Street | [way/29908209](https://www.openstreetmap.org/way/29908209) | 42.363569, -71.103365 | none |
| 4 | (unnamed) | 204 Beacon Street, Boston | [way/405331477](https://www.openstreetmap.org/way/405331477) | 42.354079, -71.077819 | none |
| 4 | (unnamed) | 205,207,209,211,213,215 Green Street | [way/29635690](https://www.openstreetmap.org/way/29635690) | 42.36401, -71.102638 | none |
| 4 | (unnamed) | 206 Beacon Street, Boston | [way/405331467](https://www.openstreetmap.org/way/405331467) | 42.35411, -71.077973 | none |
| 4 | (unnamed) | 208 Beacon Street, Boston | [way/405331282](https://www.openstreetmap.org/way/405331282) | 42.354217, -71.078159 | none |
| 4 | (unnamed) | 20;22;24;26 Columbia Street | [way/29719130](https://www.openstreetmap.org/way/29719130) | 42.364091, -71.09965 | none |
| 4 | (unnamed) | 21 Brookline Street | [way/29628669](https://www.openstreetmap.org/way/29628669) | 42.363407, -71.102443 | none |
| 4 | (unnamed) | 21 Decatur Street | [way/29924279](https://www.openstreetmap.org/way/29924279) | 42.361651, -71.106038 | none |
| 4 | (unnamed) | 21 Magazine Street, Cambridge | [way/1206008564](https://www.openstreetmap.org/way/1206008564) | 42.364004, -71.105546 | none |
| 4 | (unnamed) | 21 Valentine Street | [way/29792626](https://www.openstreetmap.org/way/29792626) | 42.3606, -71.106053 | none |
| 4 | (unnamed) | 21 William Street | [way/29794525](https://www.openstreetmap.org/way/29794525) | 42.36353, -71.105804 | none |
| 4 | (unnamed) | 210 Beacon Street, Boston | [way/405331375](https://www.openstreetmap.org/way/405331375) | 42.354235, -71.078323 | none |
| 4 | (unnamed) | 210;212;214;216 Green Street | [way/29923420](https://www.openstreetmap.org/way/29923420) | 42.363716, -71.102694 | none |
| 4 | (unnamed) | 212 Beacon Street, Boston | [way/405331302](https://www.openstreetmap.org/way/405331302) | 42.354023, -71.078033 | none |
| 4 | (unnamed) | 214 Beacon Street, Boston | [way/29744571](https://www.openstreetmap.org/way/29744571) | 42.354296, -71.078702 | none |
| 4 | (unnamed) | 216 Beacon Street, Boston | [way/405331339](https://www.openstreetmap.org/way/405331339) | 42.353608, -71.077653 | none |
| 4 | (unnamed) | 216,218 Franklin Street | [way/29591552](https://www.openstreetmap.org/way/29591552) | 42.363522, -71.103804 | none |
| 4 | (unnamed) | 217;219 Green Street | [way/29633430](https://www.openstreetmap.org/way/29633430) | 42.36419, -71.102971 | none |
| 4 | (unnamed) | 21;23 Bishop Allen Drive, Cambridge | [way/29806971](https://www.openstreetmap.org/way/29806971) | 42.364051, -71.099064 | none |
| 4 | (unnamed) | 22 Decatur Street | [way/29680382](https://www.openstreetmap.org/way/29680382) | 42.361404, -71.106266 | none |
| 4 | (unnamed) | 22 Lopez Street | [way/29938151](https://www.openstreetmap.org/way/29938151) | 42.361267, -71.104612 | none |
| 4 | (unnamed) | 22 Suffolk Street | [way/29935866](https://www.openstreetmap.org/way/29935866) | 42.366134, -71.099765 | none |
| 4 | (unnamed) | 220 Beacon Street, Boston | [way/405331526](https://www.openstreetmap.org/way/405331526) | 42.354082, -71.078582 | none |
| 4 | (unnamed) | 220;222 Franklin Street | [way/29937215](https://www.openstreetmap.org/way/29937215) | 42.363325, -71.103478 | none |
| 4 | (unnamed) | 222 Beacon Street, Boston | [way/405331237](https://www.openstreetmap.org/way/405331237) | 42.353968, -71.078589 | none |
| 4 | (unnamed) | 226 Beacon Street, Boston | [way/405331455](https://www.openstreetmap.org/way/405331455) | 42.354099, -71.078865 | none |
| 4 | (unnamed) | 22;24 Magazine Street, Cambridge | [way/1025869483](https://www.openstreetmap.org/way/1025869483) | 42.363769, -71.10567 | none |
| 4 | (unnamed) | 22;24 Watson Street | [way/29904548](https://www.openstreetmap.org/way/29904548) | 42.362194, -71.10477 | none |
| 4 | (unnamed) | 23 Pine Street | [way/212292611](https://www.openstreetmap.org/way/212292611) | 42.364163, -71.097919 | none |
| 4 | (unnamed) | 23,25 William Street | [way/29790295](https://www.openstreetmap.org/way/29790295) | 42.363732, -71.106173 | none |
| 4 | (unnamed) | 230 Beacon Street, Boston | [way/405331533](https://www.openstreetmap.org/way/405331533) | 42.354148, -71.079083 | none |
| 4 | (unnamed) | 232 Beacon Street, Boston | [way/405331371](https://www.openstreetmap.org/way/405331371) | 42.353986, -71.078962 | none |
| 4 | (unnamed) | 233;239;243;245;259 Massachusetts Avenue | [way/29609874](https://www.openstreetmap.org/way/29609874) | 42.361787, -71.097196 | none |
| 4 | (unnamed) | 234 Beacon Street, Boston | [way/405331484](https://www.openstreetmap.org/way/405331484) | 42.354098, -71.079263 | none |
| 4 | (unnamed) | 238 Main Street, Cambridge | [way/1047765107](https://www.openstreetmap.org/way/1047765107) | 42.361675, -71.084722 | none |
| 4 | (unnamed) | 23;25 Decatur Street | [way/29926252](https://www.openstreetmap.org/way/29926252) | 42.361185, -71.105312 | none |
| 4 | (unnamed) | 24 Decatur Street | [way/29680381](https://www.openstreetmap.org/way/29680381) | 42.360887, -71.105384 | none |
| 4 | (unnamed) | 24 Fiske Place | [way/29586507](https://www.openstreetmap.org/way/29586507) | 42.365385, -71.100121 | none |
| 4 | (unnamed) | 240 Franklin Street, Cambridge | [way/29929091](https://www.openstreetmap.org/way/29929091) | 42.363858, -71.104455 | none |
| 4 | (unnamed) | 240;242 Albany Street | [way/29637303](https://www.openstreetmap.org/way/29637303) | 42.358323, -71.100878 | none |
| 4 | (unnamed) | 241 Washington Street | [way/221233962](https://www.openstreetmap.org/way/221233962) | 42.364902, -71.096241 | none |
| 4 | (unnamed) | 245;247;247A Washington Street | [way/1006817433](https://www.openstreetmap.org/way/1006817433) | 42.364956, -71.096413 | none |
| 4 | (unnamed) | 246 Franklin Street, Cambridge | [way/29941403](https://www.openstreetmap.org/way/29941403) | 42.364329, -71.105473 | none |
| 4 | (unnamed) | 248 Franklin Street, Cambridge | [way/29680270](https://www.openstreetmap.org/way/29680270) | 42.363683, -71.104087 | none |
| 4 | (unnamed) | 24;26 Lopez Street | [way/29629673](https://www.openstreetmap.org/way/29629673) | 42.361287, -71.104679 | none |
| 4 | (unnamed) | 25 Magazine Street, Cambridge | [way/29680274](https://www.openstreetmap.org/way/29680274) | 42.363557, -71.105512 | none |
| 4 | (unnamed) | 25, Cambridge | [way/1260648991](https://www.openstreetmap.org/way/1260648991) | 42.364611, -71.103252 | none |
| 4 | (unnamed) | 250 | [way/29566193](https://www.openstreetmap.org/way/29566193) | 42.365635, -71.086593 | none |
| 4 | (unnamed) | 253;255;257;259 Washington Street | [way/29802005](https://www.openstreetmap.org/way/29802005) | 42.365077, -71.096658 | none |
| 4 | (unnamed) | 254 Franklin Street, Cambridge | [way/29787831](https://www.openstreetmap.org/way/29787831) | 42.363992, -71.104632 | none |
| 4 | (unnamed) | 254 Massachusetts Avenue | [way/29946495](https://www.openstreetmap.org/way/29946495) | 42.361034, -71.097443 | none |
| 4 | (unnamed) | 26 River Street, Cambridge | [way/1206008563](https://www.openstreetmap.org/way/1206008563) | 42.364821, -71.105894 | none |
| 4 | (unnamed) | 26 Watson Street | [way/29929775](https://www.openstreetmap.org/way/29929775) | 42.36204, -71.104538 | none |
| 4 | (unnamed) | 260;280;282 Franklin Street, Cambridge | [way/29937005](https://www.openstreetmap.org/way/29937005) | 42.364636, -71.105658 | none |
| 4 | (unnamed) | 261 Washington Street, Cambridge | [way/1240145490](https://www.openstreetmap.org/way/1240145490) | 42.364896, -71.096456 | none |
| 4 | (unnamed) | 265 First Street, Cambridge | [way/29802417](https://www.openstreetmap.org/way/29802417) | 42.362959, -71.079261 | none |
| 4 | (unnamed) | 266 Massachusetts Avenue, Cambridge | [way/595628597](https://www.openstreetmap.org/way/595628597) | 42.361446, -71.097721 | none |
| 4 | (unnamed) | 266;268;270 Washington Street | [way/29866690](https://www.openstreetmap.org/way/29866690) | 42.365228, -71.09769 | none |
| 4 | (unnamed) | 27 Decatur Street | [way/29586063](https://www.openstreetmap.org/way/29586063) | 42.361619, -71.106084 | none |
| 4 | (unnamed) | 27 Watson Street | [way/29636974](https://www.openstreetmap.org/way/29636974) | 42.362593, -71.10491 | none |
| 4 | (unnamed) | 270 Albany Street, Cambridge | [way/29680566](https://www.openstreetmap.org/way/29680566) | 42.357659, -71.101929 | none |
| 4 | (unnamed) | 271;273;275 Washington Street | [way/29808347](https://www.openstreetmap.org/way/29808347) | 42.365001, -71.096839 | none |
| 4 | (unnamed) | 274;276;278;280 Washington Street | [way/29738201](https://www.openstreetmap.org/way/29738201) | 42.365261, -71.097865 | none |
| 4 | (unnamed) | 28 River Street, Cambridge | [way/1206008562](https://www.openstreetmap.org/way/1206008562) | 42.364477, -71.105467 | none |
| 4 | (unnamed) | 280 Albany Street, Cambridge | [way/29791001](https://www.openstreetmap.org/way/29791001) | 42.357746, -71.102517 | none |
| 4 | (unnamed) | 280 Green Street | [way/29922113](https://www.openstreetmap.org/way/29922113) | 42.36453, -71.104208 | none |
| 4 | (unnamed) | 281;287 Albany Street | [way/29629456](https://www.openstreetmap.org/way/29629456) | 42.357964, -71.102835 | none |
| 4 | (unnamed) | 283 Washington Street | [way/29943110](https://www.openstreetmap.org/way/29943110) | 42.365457, -71.097765 | none |
| 4 | (unnamed) | 288;290 Washington Street | [way/29650615](https://www.openstreetmap.org/way/29650615) | 42.365074, -71.097743 | none |
| 4 | (unnamed) | 288;296 Green Street | [way/29939577](https://www.openstreetmap.org/way/29939577) | 42.364742, -71.104567 | none |
| 4 | (unnamed) | 289 Washington Street | [way/1280030724](https://www.openstreetmap.org/way/1280030724) | 42.36506, -71.097156 | none |
| 4 | (unnamed) | 28;30 Lopez Street | [way/29887673](https://www.openstreetmap.org/way/29887673) | 42.361549, -71.105138 | none |
| 4 | (unnamed) | 296 Washington Street | [way/29744415](https://www.openstreetmap.org/way/29744415) | 42.36508, -71.097816 | none |
| 4 | (unnamed) | 297 Massachusetts Avenue | [way/1110799054](https://www.openstreetmap.org/way/1110799054) | 42.362253, -71.097742 | none |
| 4 | (unnamed) | 297;299 Washington Street | [way/29558540](https://www.openstreetmap.org/way/29558540) | 42.365912, -71.098754 | none |
| 4 | (unnamed) | 2;4;6;10 Columbia Terrace | [way/29635576](https://www.openstreetmap.org/way/29635576) | 42.365002, -71.099844 | none |
| 4 | (unnamed) | 2;4;6;8 Newtowne Court | [way/29942411](https://www.openstreetmap.org/way/29942411) | 42.364425, -71.095984 | none |
| 4 | (unnamed) | 3 Brookline Place | [way/993359991](https://www.openstreetmap.org/way/993359991) | 42.361376, -71.103455 | none |
| 4 | (unnamed) | 3 William Street | [way/29590796](https://www.openstreetmap.org/way/29590796) | 42.36291, -71.104825 | none |
| 4 | (unnamed) | 30 Decatur Street | [way/29890948](https://www.openstreetmap.org/way/29890948) | 42.36194, -71.107153 | none |
| 4 | (unnamed) | 30 Norfolk Street | [way/29585740](https://www.openstreetmap.org/way/29585740) | 42.364603, -71.100882 | none |
| 4 | (unnamed) | 30 Pearl Street | [way/1205570168](https://www.openstreetmap.org/way/1205570168) | 42.364148, -71.103335 | none |
| 4 | (unnamed) | 30 Pilgrim Street | [way/264253040](https://www.openstreetmap.org/way/264253040) | 42.361031, -71.10287 | none |
| 4 | (unnamed) | 30 River Street, Cambridge | [way/29788555](https://www.openstreetmap.org/way/29788555) | 42.365043, -71.106548 | none |
| 4 | (unnamed) | 300 Athenaeum Street | [way/141434946](https://www.openstreetmap.org/way/141434946) | 42.364161, -71.081 | none |
| 4 | (unnamed) | 300 Binney Street, Cambridge | [way/431782053](https://www.openstreetmap.org/way/431782053) | 42.366008, -71.088003 | none |
| 4 | (unnamed) | 300 Third Street | [way/29650603](https://www.openstreetmap.org/way/29650603) | 42.365282, -71.082021 | none |
| 4 | (unnamed) | 301 Massachusetts Avenue | [way/1110799055](https://www.openstreetmap.org/way/1110799055) | 42.362598, -71.098453 | none |
| 4 | (unnamed) | 304 Washington Street | [way/29737477](https://www.openstreetmap.org/way/29737477) | 42.365086, -71.098009 | none |
| 4 | (unnamed) | 307 Washington Street | [way/29619334](https://www.openstreetmap.org/way/29619334) | 42.365302, -71.097946 | none |
| 4 | (unnamed) | 31 Lopez Street | [way/29932420](https://www.openstreetmap.org/way/29932420) | 42.361006, -71.10363 | none |
| 4 | (unnamed) | 311;313;315;319;321;323 Massachusetts Avenue | [way/1110799056](https://www.openstreetmap.org/way/1110799056) | 42.362434, -71.098296 | none |
| 4 | (unnamed) | 319 Washington Street | [way/29946142](https://www.openstreetmap.org/way/29946142) | 42.365405, -71.098351 | none |
| 4 | (unnamed) | 32 Pearl Street | [way/1205570167](https://www.openstreetmap.org/way/1205570167) | 42.36403, -71.103255 | none |
| 4 | (unnamed) | 32 River Street, Cambridge | [way/1206008561](https://www.openstreetmap.org/way/1206008561) | 42.364864, -71.106377 | none |
| 4 | (unnamed) | 324 Massachusetts Avenue | [way/485224103](https://www.openstreetmap.org/way/485224103) | 42.362094, -71.098934 | none |
| 4 | (unnamed) | 32;34 Pine Street | [way/29608782](https://www.openstreetmap.org/way/29608782) | 42.364724, -71.098375 | none |
| 4 | (unnamed) | 33 Tudor Street | [way/132600549](https://www.openstreetmap.org/way/132600549) | 42.360333, -71.104539 | none |
| 4 | (unnamed) | 33;35 Newtowne Court | [way/29862486](https://www.openstreetmap.org/way/29862486) | 42.363412, -71.093768 | none |
| 4 | (unnamed) | 34 Pearl Street | [way/1205570166](https://www.openstreetmap.org/way/1205570166) | 42.363753, -71.102907 | none |
| 4 | (unnamed) | 344;346 Washington Street | [way/29622633](https://www.openstreetmap.org/way/29622633) | 42.365392, -71.099138 | none |
| 4 | (unnamed) | 345 Washington Street | [way/29863582](https://www.openstreetmap.org/way/29863582) | 42.36539, -71.098621 | none |
| 4 | (unnamed) | 34;36 Newtowne Court | [way/29871253](https://www.openstreetmap.org/way/29871253) | 42.363799, -71.093578 | none |
| 4 | (unnamed) | 35 Brookline Street, Cambridge | [way/29680289](https://www.openstreetmap.org/way/29680289) | 42.363127, -71.102509 | none |
| 4 | (unnamed) | 35 Landsdowne Street | [way/29934401](https://www.openstreetmap.org/way/29934401) | 42.361103, -71.099996 | none |
| 4 | (unnamed) | 35 Lopez Street | [way/29582663](https://www.openstreetmap.org/way/29582663) | 42.361928, -71.105102 | none |
| 4 | (unnamed) | 350,352 Washington Street | [way/29807754](https://www.openstreetmap.org/way/29807754) | 42.36564, -71.099732 | none |
| 4 | (unnamed) | 355 Massachusetts Avenue, Cambridge | [way/1098003654](https://www.openstreetmap.org/way/1098003654) | 42.363062, -71.099326 | none |
| 4 | (unnamed) | 358;360;362 Washington Street | [way/29580933](https://www.openstreetmap.org/way/29580933) | 42.36573, -71.099926 | none |
| 4 | (unnamed) | 359;371 Green Street | [way/29827307](https://www.openstreetmap.org/way/29827307) | 42.365717, -71.10535 | none |
| 4 | (unnamed) | 36 Pearl Street | [way/1205570165](https://www.openstreetmap.org/way/1205570165) | 42.363492, -71.102577 | none |
| 4 | (unnamed) | 361 Washington Street | [way/29627828](https://www.openstreetmap.org/way/29627828) | 42.365346, -71.098639 | none |
| 4 | (unnamed) | 363 Washington Street | [way/29938861](https://www.openstreetmap.org/way/29938861) | 42.365729, -71.099381 | none |
| 4 | (unnamed) | 368 Washington Street | [way/29794758](https://www.openstreetmap.org/way/29794758) | 42.365285, -71.099228 | none |
| 4 | (unnamed) | 372;374;376;378 Washington Street | [way/29513578](https://www.openstreetmap.org/way/29513578) | 42.365835, -71.100258 | none |
| 4 | (unnamed) | 373;375 Washington Street | [way/29584049](https://www.openstreetmap.org/way/29584049) | 42.365751, -71.099531 | none |
| 4 | (unnamed) | 37;39;41 Speridakis Terrace | [way/993369379](https://www.openstreetmap.org/way/993369379) | 42.359872, -71.105882 | none |
| 4 | (unnamed) | 38 Pearl Street | [way/29635222](https://www.openstreetmap.org/way/29635222) | 42.364166, -71.103836 | none |
| 4 | (unnamed) | 384 Washington Street | [way/29787534](https://www.openstreetmap.org/way/29787534) | 42.365851, -71.100385 | none |
| 4 | (unnamed) | 385 Washington Street | [way/29513576](https://www.openstreetmap.org/way/29513576) | 42.365971, -71.100001 | none |
| 4 | (unnamed) | 39 Bishop Allen Drive | [way/29787413](https://www.openstreetmap.org/way/29787413) | 42.364384, -71.099484 | none |
| 4 | (unnamed) | 390;394 Washington Street | [way/29628692](https://www.openstreetmap.org/way/29628692) | 42.365511, -71.099917 | none |
| 4 | (unnamed) | 395 Washington Street | [way/29822194](https://www.openstreetmap.org/way/29822194) | 42.366309, -71.100694 | none |
| 4 | (unnamed) | 3;5 Watson Street | [way/29581950](https://www.openstreetmap.org/way/29581950) | 42.362075, -71.104004 | none |
| 4 | (unnamed) | 3;5;9 Columbia Terrace | [way/29631095](https://www.openstreetmap.org/way/29631095) | 42.365102, -71.099558 | none |
| 4 | (unnamed) | 4 Bishop Allen Drive | [way/1161455922](https://www.openstreetmap.org/way/1161455922) | 42.364576, -71.100358 | none |
| 4 | (unnamed) | 4 Broad Canal Way | [way/823968941](https://www.openstreetmap.org/way/823968941) | 42.363147, -71.083473 | none |
| 4 | (unnamed) | 4 Eaton Street | [way/29618103](https://www.openstreetmap.org/way/29618103) | 42.364374, -71.097591 | none |
| 4 | (unnamed) | 4 Glenn Terrace | [way/29587564](https://www.openstreetmap.org/way/29587564) | 42.359084, -71.105081 | none |
| 4 | (unnamed) | 4 Salem Street | [way/29680309](https://www.openstreetmap.org/way/29680309) | 42.362669, -71.103963 | none |
| 4 | (unnamed) | 4 Watson Street | [way/29829399](https://www.openstreetmap.org/way/29829399) | 42.361409, -71.103472 | none |
| 4 | (unnamed) | 4 William Street | [way/1279412416](https://www.openstreetmap.org/way/1279412416) | 42.362579, -71.105234 | none |
| 4 | (unnamed) | 40 Landsdowne Street, Cambridge | [way/264253042](https://www.openstreetmap.org/way/264253042) | 42.360533, -71.099542 | none |
| 4 | (unnamed) | 40 Pearl Street | [way/1025697580](https://www.openstreetmap.org/way/1025697580) | 42.364337, -71.10425 | none |
| 4 | (unnamed) | 400 Washington Street | [way/29513577](https://www.openstreetmap.org/way/29513577) | 42.365762, -71.100375 | none |
| 4 | (unnamed) | 401 Washington Street | [way/29513575](https://www.openstreetmap.org/way/29513575) | 42.365875, -71.100002 | none |
| 4 | (unnamed) | 401;403 Massachusetts Avenue | [way/29634598](https://www.openstreetmap.org/way/29634598) | 42.363716, -71.100074 | none |
| 4 | (unnamed) | 407,409 Washington Street | [way/1168148234](https://www.openstreetmap.org/way/1168148234) | 42.365806, -71.099991 | none |
| 4 | (unnamed) | 40;42;44;46 Lopez Street | [way/29904145](https://www.openstreetmap.org/way/29904145) | 42.361547, -71.105102 | none |
| 4 | (unnamed) | 41 Linskey Way | [way/29865890](https://www.openstreetmap.org/way/29865890) | 42.364958, -71.080155 | none |
| 4 | (unnamed) | 41 Pilgrim Street | [way/29632232](https://www.openstreetmap.org/way/29632232) | 42.361739, -71.103057 | none |
| 4 | (unnamed) | 41;43 Columbia Street | [way/29513563](https://www.openstreetmap.org/way/29513563) | 42.364306, -71.098893 | none |
| 4 | (unnamed) | 42 Pearl Street | [way/1205570172](https://www.openstreetmap.org/way/1205570172) | 42.363613, -71.10316 | none |
| 4 | (unnamed) | 42 Pilgrim Street | [way/29787853](https://www.openstreetmap.org/way/29787853) | 42.36134, -71.102979 | none |
| 4 | (unnamed) | 424 Massachusetts Avenue | [way/29822938](https://www.openstreetmap.org/way/29822938) | 42.363256, -71.100646 | none |
| 4 | (unnamed) | 43 Allston Street | [way/29631600](https://www.openstreetmap.org/way/29631600) | 42.357505, -71.105901 | none |
| 4 | (unnamed) | 438 Green Street, Cambridge | [way/29938232](https://www.openstreetmap.org/way/29938232) | 42.363323, -71.101412 | none |
| 4 | (unnamed) | 44 Columbia Street | [way/29859863](https://www.openstreetmap.org/way/29859863) | 42.364499, -71.098965 | none |
| 4 | (unnamed) | 44 Pearl Street | [way/1205570169](https://www.openstreetmap.org/way/1205570169) | 42.363864, -71.103698 | none |
| 4 | (unnamed) | 45 Cherry Street | [way/29866936](https://www.openstreetmap.org/way/29866936) | 42.363927, -71.097082 | none |
| 4 | (unnamed) | 450 Kendall Street, Cambridge | [way/330241509](https://www.openstreetmap.org/way/330241509) | 42.363401, -71.081556 | none |
| 4 | (unnamed) | 450 Massachusetts Avenue, Cambridge | [way/264694971](https://www.openstreetmap.org/way/264694971) | 42.363424, -71.101288 | none |
| 4 | (unnamed) | 45;47 Pilgrim Street | [way/29926466](https://www.openstreetmap.org/way/29926466) | 42.361793, -71.103149 | none |
| 4 | (unnamed) | 45;75 Sidney Street | [way/29903351](https://www.openstreetmap.org/way/29903351) | 42.361755, -71.101963 | none |
| 4 | (unnamed) | 46 Pearl Street | [way/1205570171](https://www.openstreetmap.org/way/1205570171) | 42.36403, -71.104086 | none |
| 4 | (unnamed) | 46,48 Pilgrim Street | [way/29785905](https://www.openstreetmap.org/way/29785905) | 42.361517, -71.103372 | none |
| 4 | (unnamed) | 463 Massachusetts Avenue, Cambridge | [way/29938285](https://www.openstreetmap.org/way/29938285) | 42.364045, -71.100922 | none |
| 4 | (unnamed) | 464;468 Massachusetts Avenue | [way/1068249525](https://www.openstreetmap.org/way/1068249525) | 42.363582, -71.101332 | none |
| 4 | (unnamed) | 46;48 Norfolk Street | [way/29790431](https://www.openstreetmap.org/way/29790431) | 42.365143, -71.100907 | none |
| 4 | (unnamed) | 47 Bishop Allen Drive | [way/29791357](https://www.openstreetmap.org/way/29791357) | 42.364809, -71.100141 | none |
| 4 | (unnamed) | 47 Erie Street | [way/652167462](https://www.openstreetmap.org/way/652167462) | 42.358274, -71.104009 | none |
| 4 | (unnamed) | 47 Lopez Street | [way/29823458](https://www.openstreetmap.org/way/29823458) | 42.362035, -71.10525 | none |
| 4 | (unnamed) | 47 Pine Street | [way/29864928](https://www.openstreetmap.org/way/29864928) | 42.364783, -71.098313 | none |
| 4 | (unnamed) | 48 Lopez Street | [way/29788423](https://www.openstreetmap.org/way/29788423) | 42.36169, -71.105335 | none |
| 4 | (unnamed) | 48 Pearl Street | [way/1205570170](https://www.openstreetmap.org/way/1205570170) | 42.363312, -71.102996 | none |
| 4 | (unnamed) | 485;489 Massachusetts Avenue | [way/651855724](https://www.openstreetmap.org/way/651855724) | 42.364245, -71.101178 | none |
| 4 | (unnamed) | 48;50 Bishop Allen Drive | [way/29708710](https://www.openstreetmap.org/way/29708710) | 42.364464, -71.10029 | none |
| 4 | (unnamed) | 49 Allston Street | [way/29888584](https://www.openstreetmap.org/way/29888584) | 42.357596, -71.106058 | none |
| 4 | (unnamed) | 49 Cherry Street | [way/29568620](https://www.openstreetmap.org/way/29568620) | 42.363971, -71.097024 | none |
| 4 | (unnamed) | 49,51,53 Columbia Street | [way/29715984](https://www.openstreetmap.org/way/29715984) | 42.364783, -71.099349 | none |
| 4 | (unnamed) | 4;6 Douglass Street, Cambridge | [way/29589518](https://www.openstreetmap.org/way/29589518) | 42.364044, -71.100556 | none |
| 4 | (unnamed) | 5 Cottage Court | [way/29590965](https://www.openstreetmap.org/way/29590965) | 42.36234, -71.106228 | none |
| 4 | (unnamed) | 5,7 William Street | [way/29924969](https://www.openstreetmap.org/way/29924969) | 42.363509, -71.105814 | none |
| 4 | (unnamed) | 50 Binney Street | [way/652081715](https://www.openstreetmap.org/way/652081715) | 42.364892, -71.079112 | none |
| 4 | (unnamed) | 50 Rogers Street | [way/1074970081](https://www.openstreetmap.org/way/1074970081) | 42.365641, -71.07886 | none |
| 4 | (unnamed) | 500 Kendall Street | [way/29563932](https://www.openstreetmap.org/way/29563932) | 42.363916, -71.081422 | none |
| 4 | (unnamed) | 500 Kendall Street | [way/29563932](https://www.openstreetmap.org/way/29563932) | 42.363916, -71.081422 | none |
| 4 | (unnamed) | 502 Massachusetts Avenue | [way/29590190](https://www.openstreetmap.org/way/29590190) | 42.363861, -71.101673 | none |
| 4 | (unnamed) | 50;52 Norfolk Street | [way/29591321](https://www.openstreetmap.org/way/29591321) | 42.365021, -71.100498 | none |
| 4 | (unnamed) | 51 Brookline Street | [way/29937997](https://www.openstreetmap.org/way/29937997) | 42.362424, -71.10244 | none |
| 4 | (unnamed) | 51 Lopez Street | [way/29904354](https://www.openstreetmap.org/way/29904354) | 42.361756, -71.104902 | none |
| 4 | (unnamed) | 51 Norfolk Street | [way/29827708](https://www.openstreetmap.org/way/29827708) | 42.365329, -71.101036 | none |
| 4 | (unnamed) | 51 Pine Street | [way/29619503](https://www.openstreetmap.org/way/29619503) | 42.36477, -71.097963 | none |
| 4 | (unnamed) | 515 Massachusetts Avenue | [way/29940417](https://www.openstreetmap.org/way/29940417) | 42.364397, -71.101442 | none |
| 4 | (unnamed) | 515 Massachusetts Avenue | [way/1159718852](https://www.openstreetmap.org/way/1159718852) | 42.364533, -71.101676 | none |
| 4 | (unnamed) | 52 Pearl Street | [way/29826619](https://www.openstreetmap.org/way/29826619) | 42.363202, -71.103189 | none |
| 4 | (unnamed) | 52;54;56;58 Bishop Allen Drive | [way/29789350](https://www.openstreetmap.org/way/29789350) | 42.36478, -71.100837 | none |
| 4 | (unnamed) | 53 Pearl Street | [way/29924716](https://www.openstreetmap.org/way/29924716) | 42.363895, -71.104696 | none |
| 4 | (unnamed) | 53;55 Bishop Allen Drive | [way/29513579](https://www.openstreetmap.org/way/29513579) | 42.364977, -71.100449 | none |
| 4 | (unnamed) | 54 Pearl Street | [way/29792868](https://www.openstreetmap.org/way/29792868) | 42.363624, -71.104098 | none |
| 4 | (unnamed) | 541;561;563;565 Massachusetts Avenue | [way/29628937](https://www.openstreetmap.org/way/29628937) | 42.364672, -71.101883 | none |
| 4 | (unnamed) | 54;56 Norfolk Street | [way/29934729](https://www.openstreetmap.org/way/29934729) | 42.365528, -71.101058 | none |
| 4 | (unnamed) | 55 Franklin Street, Cambridge | [way/328476194](https://www.openstreetmap.org/way/328476194) | 42.361464, -71.099342 | none |
| 4 | (unnamed) | 55 Norfolk Street | [way/1229554637](https://www.openstreetmap.org/way/1229554637) | 42.365141, -71.100432 | none |
| 4 | (unnamed) | 55;57;59 Columbia Street | [way/29951577](https://www.openstreetmap.org/way/29951577) | 42.365009, -71.099226 | none |
| 4 | (unnamed) | 55;57;59;61 Pearl Street | [way/29680285](https://www.openstreetmap.org/way/29680285) | 42.363284, -71.103919 | none |
| 4 | (unnamed) | 55;57;59;61 Pine Street | [way/29554575](https://www.openstreetmap.org/way/29554575) | 42.365037, -71.098175 | none |
| 4 | (unnamed) | 56 Cherry Street | [way/29714611](https://www.openstreetmap.org/way/29714611) | 42.364303, -71.097266 | none |
| 4 | (unnamed) | 56 Pearl Street | [way/29941065](https://www.openstreetmap.org/way/29941065) | 42.363612, -71.104283 | none |
| 4 | (unnamed) | 57 Bishop Allen Drive | [way/29581571](https://www.openstreetmap.org/way/29581571) | 42.365277, -71.10044 | none |
| 4 | (unnamed) | 575 Memorial Drive, Cambridge | [way/824958048](https://www.openstreetmap.org/way/824958048) | 42.35451, -71.10561 | none |
| 4 | (unnamed) | 57;59 Allston Street, Cambridge | [way/1097486355](https://www.openstreetmap.org/way/1097486355) | 42.3575, -71.105844 | none |
| 4 | (unnamed) | 589 Massachusetts Avenue, Cambridge | [way/1110799061](https://www.openstreetmap.org/way/1110799061) | 42.365189, -71.102846 | none |
| 4 | (unnamed) | 58;62;64 Norfolk Street | [way/29941879](https://www.openstreetmap.org/way/29941879) | 42.36574, -71.101 | none |
| 4 | (unnamed) | 59 Brookline Street | [way/29680318](https://www.openstreetmap.org/way/29680318) | 42.362218, -71.102473 | none |
| 4 | (unnamed) | 59 Cherry Street | [way/29717851](https://www.openstreetmap.org/way/29717851) | 42.364258, -71.097248 | none |
| 4 | (unnamed) | 59 Norfolk Street | [way/29825067](https://www.openstreetmap.org/way/29825067) | 42.366, -71.10167 | none |
| 4 | (unnamed) | 596;598;600;614 Massachusetts Avenue | [way/29680251](https://www.openstreetmap.org/way/29680251) | 42.364698, -71.103384 | none |
| 4 | (unnamed) | 599 Massachusetts Avenue, Cambridge | [way/1110799060](https://www.openstreetmap.org/way/1110799060) | 42.365226, -71.102911 | none |
| 4 | (unnamed) | 59;61 Bishop Allen Drive | [way/29634801](https://www.openstreetmap.org/way/29634801) | 42.365072, -71.100567 | none |
| 4 | (unnamed) | 5;7 Cottage Street | [way/29680320](https://www.openstreetmap.org/way/29680320) | 42.362162, -71.104943 | none |
| 4 | (unnamed) | 6 Ashburton Place | [way/29925550](https://www.openstreetmap.org/way/29925550) | 42.365776, -71.100857 | none |
| 4 | (unnamed) | 6 Cottage Court | [way/29680338](https://www.openstreetmap.org/way/29680338) | 42.362056, -71.105839 | none |
| 4 | (unnamed) | 6 Cottage Street | [way/29680328](https://www.openstreetmap.org/way/29680328) | 42.362399, -71.105871 | none |
| 4 | (unnamed) | 6 Eaton Street | [way/29947652](https://www.openstreetmap.org/way/29947652) | 42.36433, -71.097549 | none |
| 4 | (unnamed) | 6 Suffolk Street | [way/29804942](https://www.openstreetmap.org/way/29804942) | 42.366573, -71.099989 | none |
| 4 | (unnamed) | 6 William Street | [way/29890409](https://www.openstreetmap.org/way/29890409) | 42.362919, -71.105466 | none |
| 4 | (unnamed) | 60 Bishop Allen Drive, Cambridge | [way/29681508](https://www.openstreetmap.org/way/29681508) | 42.364794, -71.100906 | none |
| 4 | (unnamed) | 60 Hamilton Street | [way/29786081](https://www.openstreetmap.org/way/29786081) | 42.357954, -71.105943 | none |
| 4 | (unnamed) | 605 Massachusetts Avenue, Cambridge | [way/1110799059](https://www.openstreetmap.org/way/1110799059) | 42.365464, -71.103364 | none |
| 4 | (unnamed) | 61;63 Allston Street, Cambridge | [way/1097486356](https://www.openstreetmap.org/way/1097486356) | 42.358074, -71.106817 | none |
| 4 | (unnamed) | 61;65 Brookline Street | [way/29934918](https://www.openstreetmap.org/way/29934918) | 42.362248, -71.10311 | none |
| 4 | (unnamed) | 62 Pearl Street | [way/1063791921](https://www.openstreetmap.org/way/1063791921) | 42.362662, -71.102882 | none |
| 4 | (unnamed) | 620 Putnam Avenue | [way/29938834](https://www.openstreetmap.org/way/29938834) | 42.356233, -71.105627 | none |
| 4 | (unnamed) | 625;627;641 Massachusetts Avenue | [way/29825391](https://www.openstreetmap.org/way/29825391) | 42.365704, -71.103158 | none |
| 4 | (unnamed) | 63;65 Norfolk Street | [way/29828415](https://www.openstreetmap.org/way/29828415) | 42.365788, -71.101049 | none |
| 4 | (unnamed) | 63;65 Pine Street | [way/29863662](https://www.openstreetmap.org/way/29863662) | 42.365089, -71.09843 | none |
| 4 | (unnamed) | 63;65;67 Pearl Street | [way/29821520](https://www.openstreetmap.org/way/29821520) | 42.363062, -71.103863 | none |
| 4 | (unnamed) | 64 Pearl Street | [way/712133799](https://www.openstreetmap.org/way/712133799) | 42.363058, -71.103568 | none |
| 4 | (unnamed) | 65 Columbia Street | [way/29952553](https://www.openstreetmap.org/way/29952553) | 42.365105, -71.099026 | none |
| 4 | (unnamed) | 65 Franklin Street | [way/29826981](https://www.openstreetmap.org/way/29826981) | 42.361755, -71.100038 | none |
| 4 | (unnamed) | 65 Landsdowne Street, Cambridge | [way/29825330](https://www.openstreetmap.org/way/29825330) | 42.360608, -71.100784 | none |
| 4 | (unnamed) | 650 East Kendall Street, Cambridge | [way/141434944](https://www.openstreetmap.org/way/141434944) | 42.364482, -71.080632 | none |
| 4 | (unnamed) | 66 Bishop Allen Drive | [way/29513580](https://www.openstreetmap.org/way/29513580) | 42.3649, -71.101015 | none |
| 4 | (unnamed) | 66 Brookline Street | [way/29680308](https://www.openstreetmap.org/way/29680308) | 42.362876, -71.102706 | none |
| 4 | (unnamed) | 66;68 Pearl Street, Cambridge | [way/29589187](https://www.openstreetmap.org/way/29589187) | 42.363241, -71.104186 | none |
| 4 | (unnamed) | 66;72 Hamilton Street | [way/29905405](https://www.openstreetmap.org/way/29905405) | 42.358116, -71.106127 | none |
| 4 | (unnamed) | 67 Bishop Allen Drive | [way/29681507](https://www.openstreetmap.org/way/29681507) | 42.365466, -71.101368 | none |
| 4 | (unnamed) | 67 Columbia Street | [way/29822767](https://www.openstreetmap.org/way/29822767) | 42.365416, -71.099727 | none |
| 4 | (unnamed) | 67 Norfolk Street | [way/29681503](https://www.openstreetmap.org/way/29681503) | 42.365841, -71.100995 | none |
| 4 | (unnamed) | 675 West Kendall Street, Cambridge | [relation/65068](https://www.openstreetmap.org/relation/65068) | 42.364688, -71.082382 | none |
| 4 | (unnamed) | 68 Brookline Street | [way/29821240](https://www.openstreetmap.org/way/29821240) | 42.362517, -71.102482 | none |
| 4 | (unnamed) | 68 School Street | [way/29555197](https://www.openstreetmap.org/way/29555197) | 42.363542, -71.096637 | none |
| 4 | (unnamed) | 684,686 Massachusetts Avenue | [way/1164511134](https://www.openstreetmap.org/way/1164511134) | 42.3657, -71.104716 | none |
| 4 | (unnamed) | 68;70;72 Norfolk Street | [way/29579092](https://www.openstreetmap.org/way/29579092) | 42.365823, -71.100662 | none |
| 4 | (unnamed) | 69 Brookline Street | [way/29939729](https://www.openstreetmap.org/way/29939729) | 42.361615, -71.102222 | none |
| 4 | (unnamed) | 69 Columbia Street | [way/29820458](https://www.openstreetmap.org/way/29820458) | 42.365339, -71.099665 | none |
| 4 | (unnamed) | 698,700 Massachusetts Avenue | [way/29680231](https://www.openstreetmap.org/way/29680231) | 42.365905, -71.105096 | none |
| 4 | (unnamed) | 69;71 School Street | [way/29624091](https://www.openstreetmap.org/way/29624091) | 42.363521, -71.096268 | none |
| 4 | (unnamed) | 6;8 Salem Street | [way/29829851](https://www.openstreetmap.org/way/29829851) | 42.362518, -71.103966 | none |
| 4 | (unnamed) | 6;8 Watson Street | [way/29680353](https://www.openstreetmap.org/way/29680353) | 42.361897, -71.104292 | none |
| 4 | (unnamed) | 6;8;10 Valentine Street | [way/29680448](https://www.openstreetmap.org/way/29680448) | 42.359928, -71.105788 | none |
| 4 | (unnamed) | 6R Eaton Street | [way/29569827](https://www.openstreetmap.org/way/29569827) | 42.363869, -71.09707 | none |
| 4 | (unnamed) | 7 Green Street, Cambridge | [way/29868723](https://www.openstreetmap.org/way/29868723) | 42.361553, -71.098407 | none |
| 4 | (unnamed) | 7 Landsdowne Street | [way/595628598](https://www.openstreetmap.org/way/595628598) | 42.362128, -71.099012 | none |
| 4 | (unnamed) | 70 Bishop Allen Drive | [way/29630647](https://www.openstreetmap.org/way/29630647) | 42.364783, -71.100858 | none |
| 4 | (unnamed) | 70 Brookline Street | [way/29941915](https://www.openstreetmap.org/way/29941915) | 42.362163, -71.102285 | none |
| 4 | (unnamed) | 700 Main Street, Cambridge | [way/29804458](https://www.openstreetmap.org/way/29804458) | 42.362509, -71.095098 | none |
| 4 | (unnamed) | 700;710 Main Street, Cambridge | [way/29946359](https://www.openstreetmap.org/way/29946359) | 42.361642, -71.095168 | none |
| 4 | (unnamed) | 704,714,720 Massachusetts Avenue | [way/1164511133](https://www.openstreetmap.org/way/1164511133) | 42.365788, -71.104899 | none |
| 4 | (unnamed) | 71 Pearl Street | [way/29889074](https://www.openstreetmap.org/way/29889074) | 42.363187, -71.104712 | none |
| 4 | (unnamed) | 72 Brookline Street | [way/29637360](https://www.openstreetmap.org/way/29637360) | 42.362013, -71.102808 | none |
| 4 | (unnamed) | 72 Brookline Street | [way/1243855443](https://www.openstreetmap.org/way/1243855443) | 42.362152, -71.10338 | none |
| 4 | (unnamed) | 72 School Street | [way/29650636](https://www.openstreetmap.org/way/29650636) | 42.363736, -71.097175 | none |
| 4 | (unnamed) | 730 Main Street, Cambridge | [way/29627682](https://www.openstreetmap.org/way/29627682) | 42.362988, -71.095649 | none |
| 4 | (unnamed) | 73;75 School Street | [way/29565363](https://www.openstreetmap.org/way/29565363) | 42.364057, -71.097351 | none |
| 4 | (unnamed) | 75 Brookline Street | [way/29680339](https://www.openstreetmap.org/way/29680339) | 42.361645, -71.102709 | none |
| 4 | (unnamed) | 75 Columbia Street | [way/29942711](https://www.openstreetmap.org/way/29942711) | 42.365173, -71.098881 | none |
| 4 | (unnamed) | 750 Main Street, Cambridge | [way/29621406](https://www.openstreetmap.org/way/29621406) | 42.362834, -71.096274 | none |
| 4 | (unnamed) | 75; 125 Binney Street | [way/485224835](https://www.openstreetmap.org/way/485224835) | 42.365864, -71.080731 | none |
| 4 | (unnamed) | 75;79 Hamilton Street | [way/29581216](https://www.openstreetmap.org/way/29581216) | 42.35834, -71.105817 | none |
| 4 | (unnamed) | 77 Bishop Allen Drive | [way/29792408](https://www.openstreetmap.org/way/29792408) | 42.365593, -71.101573 | none |
| 4 | (unnamed) | 77,79 Pearl Street | [way/29938687](https://www.openstreetmap.org/way/29938687) | 42.362779, -71.104383 | none |
| 4 | (unnamed) | 78 Pearl Street | [way/1239475704](https://www.openstreetmap.org/way/1239475704) | 42.36275, -71.104006 | none |
| 4 | (unnamed) | 781;783 Main Street | [way/29802787](https://www.openstreetmap.org/way/29802787) | 42.362989, -71.096152 | none |
| 4 | (unnamed) | 782;784;790;792;796;798 Main Street | [way/29623218](https://www.openstreetmap.org/way/29623218) | 42.363026, -71.096978 | none |
| 4 | (unnamed) | 795;799;805 Main Street | [way/29865047](https://www.openstreetmap.org/way/29865047) | 42.363432, -71.097216 | none |
| 4 | (unnamed) | 79; Pine Street | [way/212292171](https://www.openstreetmap.org/way/212292171) | 42.363996, -71.098054 | none |
| 4 | (unnamed) | 7;8 Marvin Place | [way/29737957](https://www.openstreetmap.org/way/29737957) | 42.365938, -71.098147 | none |
| 4 | (unnamed) | 7;8;9 Rollins Court | [way/29632735](https://www.openstreetmap.org/way/29632735) | 42.361692, -71.104346 | none |
| 4 | (unnamed) | 7;9 Lopez Street | [way/29790763](https://www.openstreetmap.org/way/29790763) | 42.361856, -71.105111 | none |
| 4 | (unnamed) | 7;9 Salem Street | [way/29586461](https://www.openstreetmap.org/way/29586461) | 42.362624, -71.104361 | none |
| 4 | (unnamed) | 7;9 Watson Street | [way/29822303](https://www.openstreetmap.org/way/29822303) | 42.362056, -71.103988 | none |
| 4 | (unnamed) | 8 Bishop Allen Drive | [way/29864450](https://www.openstreetmap.org/way/29864450) | 42.363581, -71.098757 | none |
| 4 | (unnamed) | 8 Cottage Street | [way/29823624](https://www.openstreetmap.org/way/29823624) | 42.362228, -71.105608 | none |
| 4 | (unnamed) | 8 Douglass Street | [way/29681510](https://www.openstreetmap.org/way/29681510) | 42.364532, -71.100942 | none |
| 4 | (unnamed) | 8 Lopez Street | [way/29586212](https://www.openstreetmap.org/way/29586212) | 42.361419, -71.104836 | none |
| 4 | (unnamed) | 8 Pine Street | [way/29650628](https://www.openstreetmap.org/way/29650628) | 42.364392, -71.098624 | none |
| 4 | (unnamed) | 8 Suffolk Street | [way/29556367](https://www.openstreetmap.org/way/29556367) | 42.366264, -71.099585 | none |
| 4 | (unnamed) | 8,10 Essex Street | [way/824959630](https://www.openstreetmap.org/way/824959630) | 42.365376, -71.102568 | none |
| 4 | (unnamed) | 80 Pearl Street | [way/1239475703](https://www.openstreetmap.org/way/1239475703) | 42.36292, -71.104539 | none |
| 4 | (unnamed) | 81 Pine Street, Cambridge | [way/1193584335](https://www.openstreetmap.org/way/1193584335) | 42.365359, -71.097757 | none |
| 4 | (unnamed) | 82 Pearl Street | [way/29637809](https://www.openstreetmap.org/way/29637809) | 42.362957, -71.104891 | none |
| 4 | (unnamed) | 821;823;825 Main Street | [way/29867404](https://www.openstreetmap.org/way/29867404) | 42.363364, -71.097527 | none |
| 4 | (unnamed) | 83 Brookline Street | [way/29631891](https://www.openstreetmap.org/way/29631891) | 42.36172, -71.103154 | none |
| 4 | (unnamed) | 83;85 Pearl Street | [way/29941032](https://www.openstreetmap.org/way/29941032) | 42.363074, -71.105165 | none |
| 4 | (unnamed) | 84 Columbia Street | [way/29628281](https://www.openstreetmap.org/way/29628281) | 42.365321, -71.098329 | none |
| 4 | (unnamed) | 84,88 Auburn Park | [way/1243855444](https://www.openstreetmap.org/way/1243855444) | 42.362291, -71.103274 | none |
| 4 | (unnamed) | 84;86;88 Pine Street | [way/29650604](https://www.openstreetmap.org/way/29650604) | 42.365738, -71.098109 | none |
| 4 | (unnamed) | 85 Hamilton Street | [way/29791786](https://www.openstreetmap.org/way/29791786) | 42.358518, -71.106026 | none |
| 4 | (unnamed) | 85;87 Windsor Street | [way/29740509](https://www.openstreetmap.org/way/29740509) | 42.364241, -71.097801 | none |
| 4 | (unnamed) | 86 School Street | [way/29625102](https://www.openstreetmap.org/way/29625102) | 42.363132, -71.097105 | none |
| 4 | (unnamed) | 87 Cherry Street | [way/29611533](https://www.openstreetmap.org/way/29611533) | 42.364645, -71.096994 | none |
| 4 | (unnamed) | 875 Main Street, Cambridge | [way/1161455921](https://www.openstreetmap.org/way/1161455921) | 42.363689, -71.099074 | none |
| 4 | (unnamed) | 877 Main Street | [way/29804035](https://www.openstreetmap.org/way/29804035) | 42.363651, -71.099036 | none |
| 4 | (unnamed) | 88 Columbia Street | [way/1413042855](https://www.openstreetmap.org/way/1413042855) | 42.365799, -71.098922 | none |
| 4 | (unnamed) | 88 Pearl Street | [way/29680313](https://www.openstreetmap.org/way/29680313) | 42.36283, -71.104915 | none |
| 4 | (unnamed) | 88 School Street | [way/29568007](https://www.openstreetmap.org/way/29568007) | 42.364239, -71.098985 | none |
| 4 | (unnamed) | 884 Main Street | [way/29802646](https://www.openstreetmap.org/way/29802646) | 42.36315, -71.099127 | none |
| 4 | (unnamed) | 8;10 William Street | [way/29628855](https://www.openstreetmap.org/way/29628855) | 42.362892, -71.105491 | none |
| 4 | (unnamed) | 9 Cottage Street | [way/29634259](https://www.openstreetmap.org/way/29634259) | 42.36252, -71.105408 | none |
| 4 | (unnamed) | 9 Decatur Street | [way/1063791909](https://www.openstreetmap.org/way/1063791909) | 42.359998, -71.103375 | none |
| 4 | (unnamed) | 9 Decatur Street | [way/1316974799](https://www.openstreetmap.org/way/1316974799) | 42.360841, -71.10451 | none |
| 4 | (unnamed) | 9 Douglass Street | [way/29576906](https://www.openstreetmap.org/way/29576906) | 42.364634, -71.101064 | none |
| 4 | (unnamed) | 9 Magazine Street, Cambridge | [way/29926714](https://www.openstreetmap.org/way/29926714) | 42.3645, -71.105399 | none |
| 4 | (unnamed) | 9 Valentine Street | [way/1316974801](https://www.openstreetmap.org/way/1316974801) | 42.3605, -71.10545 | none |
| 4 | (unnamed) | 9 William Street | [way/29635974](https://www.openstreetmap.org/way/29635974) | 42.363198, -71.105314 | none |
| 4 | (unnamed) | 91 Brookline Street | [way/29786712](https://www.openstreetmap.org/way/29786712) | 42.36168, -71.103871 | none |
| 4 | (unnamed) | 91 Pearl Street | [way/1279412418](https://www.openstreetmap.org/way/1279412418) | 42.363596, -71.106538 | none |
| 4 | (unnamed) | 92 Columbia Street | [way/29627485](https://www.openstreetmap.org/way/29627485) | 42.365637, -71.098419 | none |
| 4 | (unnamed) | 92 Pearl Street | [way/29787496](https://www.openstreetmap.org/way/29787496) | 42.362217, -71.104229 | none |
| 4 | (unnamed) | 93 Windsor Street | [way/29950620](https://www.openstreetmap.org/way/29950620) | 42.363644, -71.096556 | none |
| 4 | (unnamed) | 93,95 Pearl Street | [way/1279412417](https://www.openstreetmap.org/way/1279412417) | 42.363112, -71.106135 | none |
| 4 | (unnamed) | 93;99 Bishop Allen Drive | [way/29941074](https://www.openstreetmap.org/way/29941074) | 42.365757, -71.101811 | none |
| 4 | (unnamed) | 94;96 Pine Street | [way/29859894](https://www.openstreetmap.org/way/29859894) | 42.365507, -71.097365 | none |
| 4 | (unnamed) | 94;96;98;100;102;104 Pearl Street | [way/29680325](https://www.openstreetmap.org/way/29680325) | 42.362271, -71.105046 | none |
| 4 | (unnamed) | 95 Columbia Street | [way/29619661](https://www.openstreetmap.org/way/29619661) | 42.365791, -71.098845 | none |
| 4 | (unnamed) | 95;97 School Street | [way/29622445](https://www.openstreetmap.org/way/29622445) | 42.363922, -71.098354 | none |
| 4 | (unnamed) | 96;98 Columbia Street | [way/29717524](https://www.openstreetmap.org/way/29717524) | 42.365961, -71.098711 | none |
| 4 | (unnamed) | 97 Brookline Street | [way/29937147](https://www.openstreetmap.org/way/29937147) | 42.361265, -71.103404 | none |
| 4 | (unnamed) | 97 Columbia Street | [way/29950949](https://www.openstreetmap.org/way/29950949) | 42.365404, -71.09794 | none |
| 4 | (unnamed) | 97 Pine Street | [way/29650607](https://www.openstreetmap.org/way/29650607) | 42.365743, -71.097897 | none |
| 4 | (unnamed) | 97;105 Windsor Street | [way/29565441](https://www.openstreetmap.org/way/29565441) | 42.364124, -71.096883 | none |
| 4 | (unnamed) | 98;100 Erie Street | [relation/65364](https://www.openstreetmap.org/relation/65364) | 42.358675, -71.105719 | none |
| 4 | (unnamed) | 99 Brookline Street | [way/1180978431](https://www.openstreetmap.org/way/1180978431) | 42.361348, -71.10371 | none |
| 4 | (unnamed) | 99 Erie Street, Cambridge | [way/328481775](https://www.openstreetmap.org/way/328481775) | 42.359076, -71.105317 | none |
| 4 | (unnamed) | 99;101 School Street | [way/29806118](https://www.openstreetmap.org/way/29806118) | 42.364459, -71.098993 | none |
| 4 | (unnamed) | Cambridge | [way/29589984](https://www.openstreetmap.org/way/29589984) | 42.365752, -71.10362 | none |
| 4 | (unnamed) | Massachusetts Avenue | [way/29680232](https://www.openstreetmap.org/way/29680232) | 42.365645, -71.104615 | none |

Data (c) OpenStreetMap contributors, ODbL.
