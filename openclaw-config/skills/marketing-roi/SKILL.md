# Marketing ROI

Evaluate campaign performance and channel effectiveness.

**Trigger:** User asks about marketing, campaigns, ROI, or which channel works best.

**Tables:** `marketing_campaigns`

## Steps

1. All campaigns with budget, conversions, and revenue_attributed
2. Calculate ROI: (revenue_attributed - budget) / budget
3. Calculate cost per conversion: budget / conversions
4. Rank by ROI and by cost per conversion
5. Compare channels: email vs social vs in-store vs app
6. Identify best and worst performing campaigns

## Output Format

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "One marketing ROI shot — let's see which campaigns are pulling their weight."
2. **Data Used:** Tables queried + campaign date range + budget totals
3. **Key Insights** (**bold all numbers**):
   - Best channel by ROI
   - Best individual campaign
   - Worst performer (flag for review)
4. **Visual:** Generate an Espresso Shot or Mocha Dashboard chart, then **run `data/python3 data/send_photo.py data/<chart>.png "caption"`** to deliver it to Telegram. Do NOT skip the send step.
5. **Business Recommendation:** Budget reallocation — where to invest more, where to cut
6. **Next Pour:** "Want me to forecast what a 20% budget shift would do to conversions?"
