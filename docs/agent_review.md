# Compliance agent: review of its first alerts

Run: `analysis_year = 2025`, thresholds from `dbt_project.yml`. The agent flagged four
manufacturers, all at `watch` level (three of four signals; none had a Class I recall).

| Manufacturer | Serious reports H1 -> H2 | Drugs behind the reports |
| --- | --- | --- |
| Madrigal Pharmaceuticals | 84 -> 166 (+98%) | resmetirom |
| Galderma Laboratories | 205 -> 366 (+79%) | nemolizumab, botulinum toxin A |
| TG Therapeutics | 136 -> 212 (+56%) | ublituximab |
| Ipsen Biopharmaceuticals | 264 -> 441 (+67%) | irinotecan, elafibranor, lanreotide |

## False-positive patterns

1. **New launches look like deteriorating safety.** Resmetirom, nemolizumab and elafibranor
   were approved in 2024; ublituximab in late 2022. Report counts rise as prescriptions
   ramp up, so "H2 > 1.2x H1" fires on growth in use, not growth in risk. Fix: divide by an
   exposure proxy (payment counts are a weak one; prescription volume, e.g. Medicare Part D,
   would be the right one), or require the drug to have been on the market for a full year.
2. **The concentration signal does not discriminate.** Top-decile payment share is 93-96%
   for all four and about 0.9 for the median manufacturer, so "top quartile" selects between
   very similar values. Payments to a few key opinion leaders per product are normal.
3. **Reporting artifacts.** FAERS lags real time, so late-year counts are incomplete, which
   makes H2 > H1 comparisons noisy. About 17% of drug rows cannot be tied to a manufacturer.
4. **Data window.** Adverse events in the warehouse start in 2024, so there is no multi-year
   baseline to say what a normal H1/H2 swing looks like.

None of the four is a real compliance finding. The alerts are leads for a reviewer, which
is how the brief words them.
