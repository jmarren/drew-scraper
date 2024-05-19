const express = require("express");
const router = express.Router();
const { Parser } = require("json2csv");
const puppeteer = require("puppeteer-extra");
const StealthPlugin = require("puppeteer-extra-plugin-stealth");
const cheerio = require("cheerio");
const fs = require("fs");

router.get("/", (req, res) => {
  res.send("Stealth route");
});

router.post("/scrape", async (req, res) => {
  console.log(req.body)
  const url = req.body.urlLink;
  console.log(url);
  try {
    // Launch the browser and open a new blank page
    puppeteer.use(require("puppeteer-extra-plugin-stealth")());
    const browser = await puppeteer.launch({
      args: ["--no-sandbox"],
      headless: true,
    });
    const page = await browser.newPage();

    // Navigate the page to a URL
    await page.goto(url);

    // Set screen size
    await page.setViewport({ width: 1080, height: 1024 });

    // Type into search box
    const html = await page.content();

    const $ = cheerio.load(html);



    const property = $("h1").text().trim();


    const flatData = []; // Define flatData array here

    $(".pricingGridItem").each((_, el) => {
      const modelName = $(el).find(".modelName").text().trim();
      const detailsTextWrapper = $(el).find(".detailsTextWrapper span");
      const beds = detailsTextWrapper.eq(0).text().trim();
      const baths = detailsTextWrapper.eq(1).text().trim();
      const sqFt = detailsTextWrapper.eq(2).text().trim();

      $(el).find(".allUnits .unitGridContainer .unitGridRow").each((_, el) => {
        const unit = $(el).find(".unitLabel.unitColumn span.screenReaderOnly").text().trim();
        const price = $(el).find(".unitLabel.pricingColumn span").text().trim();
        const availability = $(el).find(".unitLabel.availableColumn span.dateAvailable").text().trim();

        flatData.push({ modelName, unit, beds, baths, sqFt, price, availability, property }); // Now flatData is defined
      });
    });


    // fs.writeFileSync("floorPlans.json", JSON.stringify(flatData, null, 4), { flag: 'w' })



    const json2csvParser = new Parser();
    const csv = json2csvParser.parse(flatData);

    // Set the appropriate headers for a CSV response
    res.setHeader('Content-Type', 'text/csv');
    // res.setHeader('Content-Disposition', 'attachment; filename=\"' + `${property}.csv` + '\"');

    // Send the CSV data
    res.send(csv);

    await browser.close();
  } catch (error) {
    console.error(error);
    res
      .status(500)
      .json({ error: "An error occurred while scraping the website" });
  }
});

module.exports = router;
