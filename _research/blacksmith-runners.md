# GitHub Actions Managed Runner Alternatives — Executive Summary

**Audience:** Engineering manager evaluating whether to move off GitHub-hosted runners for a small-to-midsize TS/Python monorepo (Turborepo + pnpm + Docker, ~10–50k LoC).
**Date:** May 2026. **Bottom line up front:** For the target profile, the choice is between **Blacksmith** (lowest friction, best benchmarks, mature) and **RunsOn** (lowest per-minute cost, runs in your AWS account, ~€300/yr flat fee). Self-hosted on Hetzner only makes sense if usage is heavy and predictable AND you have an SRE who wants to own it. Depot is the right call if Docker builds dominate the wall-clock budget.

---

## 1. Status quo baseline — GitHub-hosted

GitHub announced a price reduction of up to 39% effective **Jan 1 2026**, with a new **$0.002/min "Actions cloud platform charge"** baked into hosted-runner rates. The previously announced charge on self-hosted minutes was **postponed indefinitely** after community backlash ([GitHub Changelog](https://github.blog/changelog/2026-01-01-reduced-pricing-for-github-hosted-runners-usage/), [samexpert analysis](https://samexpert.com/github-actions-pricing-backlash-2026/)).

Standard runner (2-vCPU/7GB) historically billed at $0.008/min; "larger runners" (per [GitHub Docs](https://docs.github.com/en/billing/reference/actions-runner-pricing)) at the current published rates:

| Tier | $/min Linux x64 | Notes |
|---|---|---|
| 2-core | $0.006 | New 2026 rate, includes platform charge |
| 4-core | $0.012 | |
| 8-core | $0.022 | |
| 16-core | $0.042 | |
| 32-core | $0.082 | No included minutes apply to larger runners |

**RunsOn's benchmark suite** (Passmark single-thread, [runs-on.com/benchmarks](https://runs-on.com/benchmarks/github-actions-cpu-performance/)) measures GitHub-hosted at a CPU score of **2269**, half of Blacksmith/Namespace. Cache save+restore of a 4 GB blob on GitHub runners takes **72 s** ([cache benchmark](https://runs-on.com/benchmarks/github-actions-cache-performance/)).

Free tier: standard runners free on public repos; private repos get 2,000 min/mo on the Free plan. Larger runners get **no included minutes**.

---

## 2. Provider profiles

### 2.1 Blacksmith (blacksmith.sh)

- **Pricing** ([blacksmith.sh/pricing](https://www.blacksmith.sh/pricing)): $0.004/min Ubuntu x64, $0.0025/min ARM, $0.008/min Windows, $0.08/min macOS M4. **3,000 free min/mo**, no credit card. Add-ons: Docker layer cache $0.50/GB-mo, sticky disks $0.50/GB-mo, static IP $100/IP-mo. Enterprise SLA is "contact us" (opaque).
- **Speedup:** Self-claim "2× faster, 33% cheaper" ([blacksmith.sh](https://www.blacksmith.sh/)). Independent RunsOn benchmark confirms — Blacksmith leads x64 single-thread at score 4442 vs GitHub's 2269. Cache benchmark: **25 s** total for 4 GB save+restore, the fastest measured. Real-world report from agentgateway maintainer: 10–11 min → 2–3 min E2E job ([howardjohn blog](https://blog.howardjohn.info/posts/blacksmith-gha/)).
- **Caching:** Co-located cache in the same DC as runners; transparent `actions/cache` interception; persistent Docker layer cache across runs on NVMe.
- **Drop-in:** Change `runs-on: ubuntu-latest` → `runs-on: blacksmith` (single label). Compatible with existing actions ecosystem.
- **Security:** Runs on Blacksmith's bare-metal in their colo. Ephemeral VMs per job. Code executes in **their cloud** — same trust posture as GitHub-hosted. No customer-cloud option in the public tier.
- **Ops burden:** Zero — fully managed. Auth via GitHub App install.
- **Lock-in:** Low for compute (just revert the label). Medium if you adopt their sticky-disk / cache features. No long-term contracts on self-serve.
- **Downsides:** Status page ([status.blacksmith.sh](https://status.blacksmith.sh/history/1)) shows non-trivial incident history — third-party trackers cite hundreds of small incidents in trailing 12 mo, though most are minutes-long and often upstream GitHub control-plane related. macOS pricing is steep. Static IP $100/mo each is gotcha for IP-allowlisting setups.
- **Users:** 1,200+ customers cited; testimonials from Devsisters, Cal.com, Mintlify, Tinybird ([blacksmith.sh/customers](https://www.blacksmith.sh/customers)).

### 2.2 Namespace (namespace.so)

- **Pricing** ([namespace.so/pricing](https://namespace.so/pricing)): "Compute unit" model where 1 unit = 1 vCPU + 2 GB for 1 min. A 4-vCPU/8GB shape = 4 units. Prepaid **$0.004/min**, overage **$0.006/min**. 30-day free trial.
- **Speedup:** Independent benchmark ([runs-on.com](https://runs-on.com/benchmarks/github-actions-cpu-performance/)) puts Namespace at CPU score 4410 (essentially tied with Blacksmith). Leads ARM single-thread per RunsOn benchmark. Cache benchmark **40 s** (tier 1).
- **Caching:** Heavy investment in caching primitives — cache volumes, Bazel/Turborepo integrations, remote Docker builders. This is their headline differentiator.
- **Drop-in:** `runs-on: namespace-profile-default` style label; one-line change.
- **Security:** Their cloud; ephemeral microVMs. Interactive SSH/VNC into running jobs available — powerful for debugging, but a security-review item.
- **Ops:** Fully managed. Adds value if you go deep on cache volumes, but that's also surface area to learn.
- **Lock-in:** Higher than Blacksmith if you adopt cache volumes / devboxes / remote builders — these are proprietary APIs.
- **Downsides:** Pricing model is more complex (unit math, prepaid vs overage). Smaller customer logo wall publicly.
- **Users:** Cited usage by Modal Labs, Hex, Replicate in marketing material.

### 2.3 BuildJet (buildjet.com) — **shutting down**

**Skip.** [BuildJet announced shutdown](https://buildjet.com/for-github-actions/blog/we-are-shutting-down); runners go dark **March 31, 2026**. The company stated GitHub's own improvements closed the gap they were filling. Listed only as a cautionary tale: vendor longevity is a real risk in this category.

### 2.4 Depot (depot.dev)

- **Pricing** ([depot.dev/pricing](https://depot.dev/pricing)): **$0.008/min** for `depot-ubuntu-24.04-4` (4 CPU/16 GB) — same headline rate as GitHub legacy standard. Plans: Developer $20/mo (2,000 GHA min + 500 Docker-build min + 25 GB cache), Startup $200/mo, Business custom. Cache overage $0.20/GB-mo. Per-second billing, no 1-min minimum.
- **Speedup:** Self-claim "30% faster compute, 10× cache." Independently unverifiable — **Depot's ToS forbids public benchmarking** ([noted by RunsOn](https://runs-on.com/benchmarks/github-actions-cache-performance/)). That alone is a yellow flag for an executive.
- **Caching:** Their actual moat — remote Docker builders with persistent NVMe cache disks (50 GB), eliminating the network round-trip the standard `gha` cache backend incurs. Strong story for Dockerfile-heavy projects.
- **Drop-in:** Label swap (`runs-on: depot-ubuntu-24.04`). Docker-build acceleration requires migrating to `depot/build-push-action` (more invasive).
- **Security:** Single-tenant EC2 per job ([depot.dev docs](https://depot.dev/products/github-actions)). Optional "Depot Managed" — runs in **your AWS sub-account** with their control plane. Good story for compliance-sensitive orgs.
- **Ops:** Managed. Their Docker-build product has separate concepts (projects, builders) — non-trivial mental model.
- **Lock-in:** Highest among the managed runners if you use the Docker-build product (proprietary BuildKit fork, their cache format).
- **Downsides:** Headline per-minute price isn't actually cheaper than GitHub; the savings come from the cache making jobs shorter. No-benchmarking clause is opaque.
- **Users:** PostHog, Browserbase, ReadMe, Discord cited in marketing.

### 2.5 WarpBuild (warpbuild.com)

- **Pricing** ([warpbuild.com/pricing](https://www.warpbuild.com/pricing)): **$0.008/min** for 4-vCPU/16GB. Cache $0.20/GB-mo + $0.0001/op. Per-minute billing.
- **Speedup:** Self-claim "2–10×." RunsOn benchmark: CPU score **3701** — solidly above GitHub-hosted but below Blacksmith/Namespace/RunsOn. Cache benchmark slow (110 s or failed at test time).
- **Caching:** Standard `actions/cache` drop-in plus Docker layer cache. BYOC option (deploy into your AWS/GCP) where cache is free.
- **Drop-in:** Label swap.
- **Security:** Their cloud by default; BYOC for customer-cloud.
- **Ops:** Managed; BYOC adds AWS/GCP IAM setup.
- **Lock-in:** Low.
- **Downsides:** Weakest cache numbers among the SaaS pack in independent testing. Smaller team / less public traction than Blacksmith and Namespace.
- **Users:** Marketing names Linear, Vercel — not all explicitly confirmed.

### 2.6 Ubicloud (ubicloud.com)

- **Pricing** ([ubicloud.com/use-cases/github-actions](https://www.ubicloud.com/use-cases/github-actions)): **$0.0020/min** Standard or **$0.0032/min** Premium for 4-vCPU/8GB Linux. **1,250 free min/mo**. Open-source control plane.
- **Speedup:** Self-claim "2× faster, 7× price-perf." RunsOn benchmark: Ubicloud Premium CPU score **3659** — fast but below tier-1. Cache benchmark: **116 s** (tier 2, slower than GitHub).
- **Caching:** Standard `actions/cache` compatible; no special acceleration story like Blacksmith/Namespace.
- **Drop-in:** Label swap.
- **Security:** Their cloud, ephemeral VMs per job. SOC 2 Type II. Open-source means you *could* self-host the whole stack — unusual in this market.
- **Ops:** Managed (SaaS) or self-host the OSS distribution.
- **Lock-in:** Lowest of the SaaS pack — software is open-source under AGPL/Elastic-style license.
- **Downsides:** Cache speed is mediocre. ARM support not clearly documented. Smaller US-region presence than Blacksmith.
- **Users:** Lago, Documenso publicly cited.

### 2.7 RunsOn (runs-on.com)

- **Pricing** ([runs-on.com/pricing](https://runs-on.com/pricing/)): **€300/year flat license**, **€1,500/yr** for source-code access tier. **You pay AWS directly** for EC2 — RunsOn takes no markup. A 4-vCPU c7i-flex.xlarge bills at roughly **$0.0010–0.0015/min** on EC2 on-demand. Plus ~$8/mo for the control-plane infrastructure in your account.
- **Speedup:** RunsOn-built benchmark (their own page, but methodology is documented) puts them at CPU score **4268** — tier 1 alongside Blacksmith/Namespace. Cache **42 s** (tier 1).
- **Caching:** S3-backed `actions/cache` magic-mirror — fast and cheap because it stays in your VPC.
- **Drop-in:** Label swap (`runs-on: runs-on=...,runner=4cpu-linux-x64`). One-time CloudFormation install in your AWS account.
- **Security:** **Runs entirely in your AWS account.** Single-tenant EC2 per job, ephemeral. Easy compliance / SOC 2 story because the data never leaves your tenancy.
- **Ops:** Light — CloudFormation deploys it; updates are managed. You own the AWS bill and IAM, so SRE involvement is non-zero. Spot instance support adds another ~50–70% savings if you tolerate preemption.
- **Lock-in:** Lowest. It's a license you can drop; the EC2 instances are yours.
- **Downsides:** AWS-only (no GCP/Azure today). Requires an AWS account and someone who isn't scared of CloudFormation. Single-vendor benchmark page is a minor methodology concern, though numbers track with what independent users report.
- **Users:** Public references include Modal, Anchor, several YC companies; smaller customer logo wall than Blacksmith.

### 2.8 Actuated (actuated.com)

- **Pricing** ([actuated.com/pricing](https://actuated.com/pricing)): **$150/mo first server + $125/mo per additional**, flat. **Customer brings the hardware.** Unlimited build minutes/RAM/CPU/concurrency on that hardware.
- **Speedup:** Depends entirely on your hardware. Firecracker microVMs add minimal overhead. No public independent benchmark.
- **Caching:** Bring your own — they don't provide a cache product.
- **Drop-in:** Label swap to the actuated runner pool.
- **Security:** **Strongest model** — Firecracker microVM per job, ephemeral, on your own bare metal. Code never leaves your premises. Addresses the [well-documented self-hosted runner backdoor risk](https://www.praetorian.com/blog/self-hosted-github-runners-are-backdoors/) because each job gets a fresh microVM.
- **Ops:** Highest of the managed options. You provision bare-metal (Hetzner, Equinix Metal, on-prem). Actuated manages the control plane and base images.
- **Lock-in:** Low — open-ish standards (Firecracker, GHA runner protocol).
- **Downsides:** You're responsible for capacity planning. Hardware procurement lead time. No macOS. ARM supported on appropriate hardware. Small team behind it.
- **Users:** Self-published case studies from cncf-adjacent projects, Ampere, several scale-ups.

### 2.9 Self-hosted on Hetzner

- **Pricing:** A Hetzner **CPX31** (4 vCPU AMD, 8 GB) is ~€13/mo at hourly €0.024 ([Altinity walkthrough](https://altinity.com/blog/slash-ci-cd-bills-part-2-using-hetzner-cloud-github-runners-for-your-repository)). With autoscaling via [testflows-github-hetzner-runners](https://github.com/testflows/testflows-github-hetzner-runners), per-minute effective cost is fractions of a cent.
- **Speedup:** Hetzner AMD EPYC CPUs are competitive with Blacksmith's bare metal for single-thread; multi-thread depends on the SKU. No standardized benchmark in RunsOn's suite.
- **Caching:** Roll your own (S3-compatible buckets via Hetzner Object Storage or a self-hosted Minio).
- **Drop-in:** Label swap, but you build the autoscaler.
- **Security:** **This is where it gets dangerous.** Self-hosted runners on long-lived VMs are [a documented backdoor vector](https://www.sysdig.com/blog/how-threat-actors-are-using-self-hosted-github-actions-runners-as-backdoors). You **must** use ephemeral VMs and **must not** expose them to public-repo PRs ([GitHub guidance](https://docs.github.com/en/actions/reference/security/secure-use)). The TestFlows autoscaler handles ephemerality; rolling your own is error-prone.
- **Ops:** Highest. You own the autoscaler, image baking, secret rotation, Hetzner billing reconciliation. Realistic minimum: 0.1–0.2 FTE ongoing.
- **Lock-in:** Zero infra lock-in; high *operational* lock-in to your in-house tooling.
- **Downsides:** Hetzner bills by the **hour, not the minute** — every job costs at least 1 hour of VM time unless you implement server-reuse, which then re-introduces non-ephemerality. EU-region only by default. No ARM in their cloud product (yet); Ampere bare-metal available but pricier.

---

## 3. Decision matrix

For the stated profile (TS/Python monorepo, Turborepo + pnpm, Docker builds, occasional Git LFS, 10–50k LoC):

| Need | Recommended | Why |
|---|---|---|
| **Fastest path, minimal risk** | Blacksmith | One-label change; tier-1 benchmarks; cache speed addresses pnpm/Turborepo bottleneck directly; 3,000 free min/mo covers a small team's CI. |
| **Lowest $/min, willing to own AWS** | RunsOn | Tier-1 perf for ~$0.001–0.0015/min EC2. €300/yr flat. Compliance story is best in class — code stays in your tenancy. |
| **Docker builds dominate wall-clock** | Depot | Their remote builder + persistent layer cache shortens image build by 5–10× in typical cases. Worth the lock-in if `docker build` is on the critical path. |
| **Compliance / regulated industry** | RunsOn or Actuated | Both keep code in customer-controlled infrastructure. Actuated additionally satisfies "no public cloud" requirements. |
| **Open-source / vendor-portable** | Ubicloud | OSS control plane means an exit ramp exists even if the SaaS goes away. |
| **You already run a fleet of bare-metal** | Actuated | Cheapest per-minute *if* hardware is sunk cost; microVM isolation is enterprise-grade. |
| **DIY, heavy & predictable usage, EU-based** | Hetzner self-hosted | Cost floor is unbeatable, but only if your team genuinely wants the operational responsibility. |

### When the math does **NOT** work

- **Tiny CI footprint (<1,000 min/mo):** Stay on GitHub-hosted. After the 2026 price cut, 2-vCPU at $0.006/min is fine; any alternative's setup tax outweighs savings.
- **Public OSS repo with no sponsor budget:** GitHub-hosted is free for public repos; alternatives generally aren't. Blacksmith and Namespace have OSS sponsorship programs — apply.
- **Mostly macOS or Windows:** Managed-runner Linux savings don't apply. macOS pricing on Blacksmith ($0.08/min) is *higher* than GitHub-hosted macOS in some configs.
- **Bursty + low total volume:** Flat-fee models (RunsOn €300/yr, Actuated $150/mo) become per-minute-expensive below ~5,000 min/mo. Stay pay-as-you-go.
- **Strict no-third-party-code-execution policy:** Rules out everything except RunsOn (your AWS), Actuated (your metal), and self-hosted.

### Risk callouts for the EM

1. **Vendor longevity is real.** BuildJet — a top-3 player a year ago — is dark March 31, 2026. Pick a vendor with either revenue scale (Blacksmith claims 1,200+ customers, 12× YoY revenue growth) or an OSS exit (Ubicloud, Actuated).
2. **"2× faster" claims compound with caching, not raw CPU.** A 4 GB cache restore that takes 14 s on Blacksmith vs 72 s on GitHub (5×) often matters more than the CPU delta for pnpm + Turborepo workflows where cache hits are common ([cache benchmark](https://runs-on.com/benchmarks/github-actions-cache-performance/)).
3. **Benchmarking restrictions are a tell.** Depot's "no public benchmarks" clause means you cannot validate their claims pre-purchase. Negotiate a trial.
4. **Self-hosted runner security is non-trivial.** Persistent runners can be turned into [persistent backdoors](https://www.praetorian.com/blog/self-hosted-github-runners-are-backdoors/). If you go self-hosted, ephemeral-per-job is mandatory and a checklist item, not optional.
5. **Billing surprises:** Blacksmith static IPs ($100/IP/mo), Depot cache overages ($0.20/GB-mo), Hetzner hourly minimum billing. Cap and alert on spend.

### Recommendation for a conjure-sized monorepo

1. **Default choice: Blacksmith.** Lowest activation energy, tier-1 benchmarks, generous free tier. Realistic monthly cost for a 10-person team running ~20,000 CI min: ~$68 after free tier, vs ~$120 on GitHub-hosted 2-vCPU at the new 2026 rate, with ~2× wall-clock improvement.
2. **If Docker image build is >30% of pipeline wall-time:** add **Depot for the Docker step only** (keep Blacksmith for the rest). The two compose cleanly — Depot's `depot/build-push-action` runs from any runner.
3. **If you have a senior SRE who wants to own it and you're already AWS-heavy:** **RunsOn** instead of Blacksmith. ~50% lower per-minute cost, code stays in your VPC, identical perf tier. €300/yr is rounding-error.
4. **Skip:** WarpBuild (mediocre cache benchmarks), Ubicloud (mediocre cache), BuildJet (shutting down), Actuated (overkill unless you have the hardware), pure Hetzner self-hosted (not worth the FTE-time at 10–50k LoC scale).

---

## Sources

- [GitHub Actions runner pricing docs](https://docs.github.com/en/billing/reference/actions-runner-pricing)
- [GitHub Changelog: 2026 reduced pricing](https://github.blog/changelog/2026-01-01-reduced-pricing-for-github-hosted-runners-usage/)
- [GitHub Actions pricing backlash analysis (samexpert)](https://samexpert.com/github-actions-pricing-backlash-2026/)
- [Blacksmith pricing](https://www.blacksmith.sh/pricing) · [customer stories](https://www.blacksmith.sh/customers) · [status](https://status.blacksmith.sh/history/1)
- [Namespace pricing](https://namespace.so/pricing)
- [BuildJet shutdown notice](https://buildjet.com/for-github-actions/blog/we-are-shutting-down)
- [Depot pricing](https://depot.dev/pricing) · [GitHub Actions product page](https://depot.dev/products/github-actions)
- [WarpBuild pricing](https://www.warpbuild.com/pricing)
- [Ubicloud GitHub Actions](https://www.ubicloud.com/use-cases/github-actions)
- [RunsOn pricing](https://runs-on.com/pricing/) · [CPU benchmark](https://runs-on.com/benchmarks/github-actions-cpu-performance/) · [cache benchmark](https://runs-on.com/benchmarks/github-actions-cache-performance/)
- [Actuated pricing](https://actuated.com/pricing)
- [Hetzner runner setup walkthrough (Altinity)](https://altinity.com/blog/slash-ci-cd-bills-part-2-using-hetzner-cloud-github-runners-for-your-repository) · [testflows autoscaler](https://github.com/testflows/testflows-github-hetzner-runners)
- [GitHub: self-hosted runner secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [Praetorian: self-hosted runners as backdoors](https://www.praetorian.com/blog/self-hosted-github-runners-are-backdoors/)
- [Sysdig: threat actors using self-hosted runners](https://www.sysdig.com/blog/how-threat-actors-are-using-self-hosted-github-actions-runners-as-backdoors)
- [howardjohn: real-world Blacksmith experience](https://blog.howardjohn.info/posts/blacksmith-gha/)
- [Northflank: 2026 pricing alternatives roundup](https://northflank.com/blog/github-pricing-change-self-hosted-alternatives-github-actions)
