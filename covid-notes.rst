July 2, 2020
=============

The virus
----------

As of today, the United States has had 130 thousand deaths out of 2.74 million confirmed cases.  This gives us an estimated CFR of ~5%, which is in line with the 6% estimate from a few weeks ago.

This week, the `CDC <https://www.cdc.gov/coronavirus/2019-ncov/cases-updates/commercial-lab-surveys.html>`_ reported results from antibody studies which seemed to show actual case rates were more than 10x higher than confirmed cases.  I'd honestly love to believe this is true, because if it is, it means the IFR is somewhere around 0.5%.  However, I think there are some reasons to be cautious here. 

* First, and I hate saying this, the CDC has come under a lot of political pressure.  That may be biasing the results.  
* Second, the absolute infection rates in most of the regions studied is low.  From the linked to paper, the false positive rate on the test used was just under 1%.  That would seem to put the results out of the range of likely error, but it does mean the claimed ratios are potentially too high.  In particular, the highest claimed ratios appear to be from the lowest absolute percentages (and thus most influenced by false positives.)  
* Third, and this is the biggest one, the data is old.  The most recent reported result is from May 2nd.  For a result published almost 60 days later, that is flat out suspicious.  

Putting it all together, I'd be willing to say that case rates are at least 4-5x higher than confirmed via testing based on these results, but I wouldn't go beyond that.  (As much as I'd like to.)

Treatments
-----------

A couple weeks back, we learned that `dexamethasone <https://www.nature.com/articles/d41586-020-01824-5>`_, a common steroid, appears to reduce death rates in severly ill covid patients by about 20%.  This is wonderful news, both because it would reduce our observed CFR, and also because this is a generic medication which is already widely available and *cheap* (less than $8 per dose).  That is by far the best news we've gotten to date.

This week, we're seeing efforts to `scale the collection and distribution <https://www.wsj.com/articles/u-s-seeks-large-scale-expansion-of-blood-plasma-collection-for-covid-19-11593691200>`_ of blood plasma from recovered covid patients.  As mentioned previously, we have good reason to believe that such a strategy works, and can help reduce the severity for many patients.

Putting these two together, that's a dang good bit of news.  I expect we'll start seeing the CFR trending downward over the next few months.  There's some hope we're already seeing that in the national data, but there's also a bunch of other interpretations possible there.  

I will note that I remain sceptical of the possibility of a widely deployed vaccine within the next 12 months.  I suspect we will see one, but almost certainly not this year, and next year is a merely a hope.  In theory, timelines could be accelerated with good planning and coordination, but we haven't exactly seen much evidence of that recently.  


June 12, 2020
==============

On the topic of antibody studies, we do have one small update from NY State `in minority cummuniy churches <https://www.governor.ny.gov/news/amid-ongoing-covid-19-pandemic-governor-cuomo-announces-results-states-antibody-testing-survey>'_.  I am increasing nervous at the fact the state of NY has not been publishing updates to their antibody study.  

Despite the relatively scarcity of new data, it seems like there is an emerging consensus that the infection fatility rate for COVID-19 is somewhere slightly under 1%.  The case fatality rate on the other hand seems to be hovering right around 6% for all of the data sets we have.  At the national level, we currently have 2.1 million confirmed cases, and 116 thousand deaths for a CFR of 5.5%.  As discussed previously, deaths are skewed very strongly towards the elderly, so what these numbers look like in each community is strongly dependent on demographics, but the rough numbers give us a rough idea of what we're looking at.  

One correction to the writeup below.  The study I referenced on hydroxychloroquine has been heavily critized and retracted.  Other studies are still supporting a fairly skeptical attidute here, but the study which initially appeared fairly conclusive turned out not to be.  

May 24, 2020
============

What do we know about the virus?
---------------------------------

The number of deaths per *confirmed case* is disturbingly high.  The NYC numbers [1]_ as of today are 195,452 cases, with 16,469 confirmed deaths and another 4,747 probable.  This works out to a more than 10% death rate, concentrated almost entirely in older adults [2]_.

Thankfully, there's a big difference between *confirmed cases* and *number of people infected*.  The best evidence we have to date is the new york antibody study [3]_ found 24.7% of the population to be positive for antibodies implying they had been previously infected.  With a population of 8.6 million that would mean actual case counts were around 2.1 million, ad that the death rate is actually closer 1%.  It does make me nervous that the last update on these numbers I can find is now three weeks old though.  

There is no evidence for reinfection at this time.  There were some initial reports from South Korea of potential reinfection cases, but those have now been thoroughly disproven.  The cases in question were either false positive on tests, or individuals shedding *dead* virus.  From other viruses in the same family, we have every reason to expect a prolonged immutity period of at least a couple of years.  Neither point is confirmed yet, but we can be reasonable confident that if there wasn't a substaintial period of at least partial immunity that we'd have seen that by now.  

There is some evidence of lasting effects even in younger people.  However, all of the cases reported so far are in very small absolute numbers.  That might change, but at the moment, we have no reason to believe that any large fraction of the population has long term complications following recovery.  

I have focused on the NYC data - mostly because it's the largest sample size with the fewest known bias problems - but the same general picture appears everywhere else we have data as well.

Implications
-------------

One key statement is that for most of the US, containment has failed and is no longer a viable strategy.  This is definitely true in NYC; there's no possible way to contact trace 100s of thousands of cases.  This is not true for many other areas of the country which have much lower case counts which is one legitimate reason that responses will and should differ in different locations.

Given that, we're basically looking at having to let this burn through the general population.  The only good news is that a) the death rate seems to be about 1%, b) it appears to be heavily concentrated in older adults, and c) at least in NYC we appear to be at least a fourth of the way there.  Putting that in perspective, roughly 0.8% of the population dies from natural causes each year.  Given that, we're talking about an effective doubling of the annual death rate.  That's horrible, but it's also nowhere near a worst case scenario.  

Treatments
-----------

We strongly suspect that plasma treatments work [4]_.  They're hard to scale, but we have every reason to believe from history that the approach is workable and we have a number of studies which confirm this.

We know that remdesivir shortens recovery times [5]_.  It may also have a small effect on mortality, but that's unclear.  The important part is that by shortening recovery times by roughly 30%, our hospital capacity is effective increased by 40%.  That's huge because it helps us be a lot more confident we can avoid the hospital overload scenarios which could drive the death rates through the roof.

Despite what certain idiots might tell you, we know that hydroxychloroquine does not help [6]_ and actually appears to harm.  There's still room for further evidence here changing the picture, but at the moment, it looks like taking any of the drugs in this family is a damn bad idea.

I consider the odds of having an effective vaccine widely available before this has finished burning through the general population to be quite low.  I'd love to be suprised, but at the moment, I'm assuming this is a non-factor.  

A few weeks ago, there were reports [7]_ that survival rates for patients placed on mechanical ventalators were very low.  Unfortunately, the media badly misreported this study.  The reality is that more than 50% of the patients in the study were still in treatment (i.e. alive at the time of publication).  The scary numbers everyone (including me) saw were reporting the fraction of people who'd died out of those who'd either died or recovered at that point in time.  Until we have updated numbers - which oddly, I haven't seen yet - the results could be anywhere between a 60% recovery rate and a 90% death rate.  Really, we have no idea.  





References
----------

.. [1] https://www1.nyc.gov/site/doh/covid/covid-19-data.page

.. [2] https://www.statista.com/statistics/1109867/coronavirus-death-rates-by-age-new-york-city/

.. [3] https://www.livescience.com/covid-antibody-test-results-new-york-test.html

.. [4] https://www.nature.com/articles/d41587-020-00011-1

.. [5] https://arstechnica.com/science/2020/05/the-antiviral-remdesivir-shortens-covid-19-recovery-times-study-shows/

.. [6] https://arstechnica.com/science/2020/05/hydroxychloroquine-linked-to-increase-in-covid-19-deaths-heart-risks/

.. [7] https://www.bloomberg.com/news/articles/2020-04-22/almost-9-in-10-covid-19-patients-on-ventilators-died-in-study
