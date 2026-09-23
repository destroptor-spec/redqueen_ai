# Holding and independent factory-gate review

Reviewed 2026-09-22. No simulation changes or new match launches.

## Evidence scope

All 18 `/tmp/rq-m-mexplace-*.log` files passed `scripts/analyze-log.py` in this review. Outputs are saved beside this report. All manifests identify payload `acc05419c5d5790a0928cac02cdf57777f6697b74bc2c4ebb408829381230ab1`; all Red Queen army-2 income contracts are 1v1, income=1.00. Manifest hashes for EconomyManager, StrategyDirector, ProductionManager and FortificationBuilders match the current files. Counts use army 2 only.

## Holding: distinguish quantity from coverage

StrategyDirector requests 4–12 ground defences, ceil(surface threat / 12), only under an active alert. FortificationBuilders counts allied matching-tier structures within the base manager radius (minimum 40), without checking weapon coverage of the threatened approach. Construction uses BuildClose at that base. Thus base-wide count can satisfy demand without proving protection of exposed resource sites. This is a code-level possibility, not a measured cause of losses.

There were 1,421 managed emergency-defence deferral messages, 20 direct emergency-defence queue messages and one no-engineer block message. These are events, not completed structures or lost opportunities. Managed deferral means the registered builders own the job; it does not establish that they execute it.

The earlier raised-defence experiment was bundled with storage changes. Its outcome cannot isolate the cost of extra defences; see docs/balance/storage-placement.md, Conditions for another experiment.

Next discriminating measurement: for a threatened resource group, record observed attack direction, completed and in-progress defences, actual weapon coverage, requested target, selected builder/placement, funding and completion, followed by retained extractors. Compare a local coverage policy or a defence-only quantity treatment separately from storage and factory changes. An army-wide PD total is insufficient to attribute holding failure.

## Factory gate: sampled timer effect is absent

941 periodic samples: 68 Opening, 181 Recover, 659 Balanced, 33 ExpandProduction. Of the 33 ExpandProduction samples, 18 are below the logged factory target and above the minimum mass income. These remain eligibility samples, not completed factories.

Only one Opening sample has both sufficient mass income and spare logged factory capacity. None simultaneously passes even the necessary storage conditions for surplus, using the preceding watch line. Rounded storage values at the thresholds were conservatively included. Therefore none of the recorded Opening samples establishes an expansion opportunity unlocked by removing only the timer. Missing trend values cannot change that negative necessary-condition result; minute sampling can miss opportunities between samples.

There are 81 `production expansion type=` messages across the 18 logs. These report accepted custom build requests, not completions. Consequently 3.5% time spent in ExpandProduction does not quantify the fraction of factories created by native builders. That requires attribution of completed factory entities to their construction requests.

The cheap independent next measurement is per-production-update counterfactual eligibility: current gate versus timer removed, with surplus, minimum income, exact desired capacity, domain target, cooldown and builder availability separately recorded. A separate surplus-policy treatment would test a different hypothesis from timer removal. Neither should be bundled into the holding intervention.

Machine-readable sample counts are in sample-counts.json. Analyzer statuses are in analysis-gates.json.
