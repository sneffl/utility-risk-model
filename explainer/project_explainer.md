# About My Project: Utility Non-Payment Risk and Consequence Model

Hugo Garcia Moreno

Try it here: **https://hugogarcia.shinyapps.io/utility-risk-model/**

This is a web app I built in R. You put in your monthly electricity usage and it forecasts your bill from real weather data, shows what a sudden heatwave or cold snap would do to it, maps out how an unpaid bill turns into a disconnection month by month, and calculates what a utility debt could cost you on a car loan if it ever reaches collections. This page explains how it works and where the numbers come from.

## Why I built it

This one is personal. I grew up in a household where the electric bill was a source of stress, and as a kid I felt that stress without understanding any of it. Nobody around me could answer the basic questions. When does the late fee hit? When can they legally shut the power off? The not knowing was its own weight on top of the money itself. Credit wasn't part of the worry back then. I didn't even know what a credit score was, and plenty of families get by without credit in the picture at all. Learning later how much credit quietly decides what everything costs is why the tool covers that side too.

Years later I went looking for real answers and found that in New York the whole timeline is written into a law called HEFPA, which almost nobody reads. The credit question surprised me most. A missed utility bill by itself usually does not touch your credit score. It only becomes a problem if the debt gets sold to a collection agency. I wish someone had been able to tell my family that. So I built the tool I wanted us to have, something that shows a household exactly what to expect and when, so the stress at least comes with a map.

## What the app does

The first tab forecasts your monthly bill. It uses a method utilities actually use, called degree days, which measures how far each day's temperature sits from 65 degrees. Hotter or colder days mean more heating or cooling, which means a bigger bill. I trained it on a full year of real New York City temperature records and checked the summer numbers against a published industry average so the dollar amounts are believable.

The second tab has a weather shock button. Every click generates a random extreme event, so a heatwave or cold snap with random length and severity, and shows how your bill responds. No two clicks give the same event.

The third tab shows the disconnection timeline. A bill can be current, late, seriously late, or disconnected, and each month it can move between those states with certain probabilities. That structure is called a Markov chain. The app runs the math forward and tells you the chance of disconnection within a year and the expected number of months before it happens, based on your risk level and how big the bill is compared to your income.

The last tab is the money side. It stacks up late fees over time and then shows the bigger hidden cost. If the debt reaches collections and your credit score drops, your next car loan gets a worse interest rate. I used Experian's published rate table by credit tier to turn that score drop into actual dollars.

## Where the data comes from

The risk model behind the app was trained on a public research dataset from a real utility, with three years of daily meter readings for 33,787 actual customers. I wrote code that turns each customer's usage history into twelve statistical features, things like volatility, missing readings, and long term decline, and trained two classifiers on them. On held out test data the better model scored an AUC of 0.755, which means if you hand it one flagged account and one normal account, it ranks the flagged one as riskier about 75 percent of the time.

One part is assumed rather than measured, and I say so everywhere it appears. Nobody publishes data tracking individual customers moving from late to seriously late to disconnected month by month, so the Markov chain's transition probabilities are stated assumptions that I anchored to the trained risk model where I could. Being upfront about that line matters more to me than pretending everything was fitted to data.

## Questions I get asked

**Is that AUC good?** It's solid for this problem. The dataset is imbalanced, about 89 percent normal accounts and 11 percent flagged, so raw accuracy would be misleading. AUC handles that, and 0.755 from usage patterns alone, with no payment history or demographics, is a real signal.

**Why a Markov chain?** Because a bill's life is a chain of monthly states, and the question people care about is "how long until disconnection." Markov chains have a clean piece of math called the fundamental matrix that answers exactly that. I implemented it myself in base R with matrix algebra instead of using a package, because I wanted to understand it, and it's the kind of thing I could walk through on a whiteboard.

**What was the hardest bug?** Early on, the weather shock made bills go down. A heatwave lowered the bill, which made no sense. The cause was a units mistake in how many shock days got blended into the month, plus measuring the temperature spike from the wrong baseline. Finding it taught me to test outputs against physical common sense, not just check that the code runs.

**Did you use AI tools?** Yes, as a collaborator, the way you'd work with a tutor. I directed the project, made the design calls, and can explain every method in it. I'd rather say that plainly than dodge it, since the whole project is built on being honest about what's measured and what's assumed.

**What's next for it?** If a utility ever shared anonymized delinquency records, I'd fit the transition probabilities to real data instead of assumptions. I'd also add more cities, since right now the weather model is NYC only. The full codebase and statistical report are public at github.com/sneffl/utility-risk-model.
