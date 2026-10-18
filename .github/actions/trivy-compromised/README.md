# trivy-compromised (simulation)

A local composite action that stands in for the compromised `trivy-action` release
described in the TeamPCP advisory. It never runs the real thing. The behaviours it
simulates (harmlessly) are chosen from the advisory's IoC analysis and documented here
when they are added. Until then it prints a marker line and exits 0.
