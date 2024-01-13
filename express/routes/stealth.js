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

    const units = [];

    $(".unitGridRow").each((i, el) => {
      const unit = $(".unitLabel.unitColumn span.screenReaderOnly", el)
        .text()
        .trim();
      const price = $(".unitLabel.pricingColumn span", el).text().trim();
      const sqft = $(".unitLabel.sqftColumn span", el).text().trim();
      const availability = $(
        ".unitLabel.availableColumn span.dateAvailable",
        el
      )
        .text()
        .trim();

      units.push({ unit, price, sqft, availability });
    });

    console.log(units);

    const json2csvParser = new Parser();
    const csv = json2csvParser.parse(units);

    // Write CSV to a file
    fs.writeFileSync("units.csv", csv);

    // Send the file
    res.download("units.csv");

    await browser.close();
  } catch (error) {
    console.error(error);
    res
      .status(500)
      .json({ error: "An error occurred while scraping the website" });
  }
});

module.exports = router;
