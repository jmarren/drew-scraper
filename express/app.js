const express = require("express");
const axios = require("axios");
const cheerio = require("cheerio");
const fs = require("fs");
const path = require("path")
const cors = require("cors");
const { Parser } = require("json2csv");
const puppeteer = require("puppeteer-extra");
const StealthPlugin = require("puppeteer-extra-plugin-stealth");
const stealthRouter = require("./routes/stealth");
const PORT = process.env.PORT || 3014;

const app = express();


app.use(express.json({ limit: "50mb" }));

// Set up CORS
const whitelist = [
  "http://localhost:3007",
  "https://droopy.mechanicalturk.one",
  "http://localhost:3011",
  "http://localhost:3000"
];



const corsOptions = {
  origin: function(origin, callback) {
    if (!origin || whitelist.indexOf(origin) !== -1) {
      callback(null, true);
    } else {
      callback(new Error("Not allowed by CORS"));
    }
  },
  optionsSuccessStatus: 200,
};
app.use(cors(corsOptions));

app.get("/", (req, res) => {
  res.send("Hello World!");
});


app.get("/localHTML", (req, res) => {
  try {
    const html = fs.readFileSync("./pageSource.html", "utf-8");
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

    res.json({
      units,
    });
  } catch (error) {
    console.error(error);
    res
      .status(500)
      .json({ error: "An error occurred while scraping the website" });
  }
});

// app.post("/scrape", async (req, res) => {
//   // const filePath = path.join(__dirname, 'requestBody.json');
//   //
//   // // Convert the request body to a JSON string
//   // const data = JSON.stringify(req.body, null, 2);
//
//   // Write the data to a new file
//   // fs.writeFile(filePath, data, (err) => {
//   //   if (err) {
//   //     console.error('Error writing file:', err);
//   //     return res.status(500).send('Error writing file');
//   //   }
//   //
//   //   console.log('File has been saved.');
//   // });
//   try {
//     const html = req.body.inputValue;
//     console.log(html);
//
//     const $ = cheerio.load(html);
//
//     const units = [];
//
//     $(".unitGridRow").each((i, el) => {
//       const unit = $(".unitLabel.unitColumn span.screenReaderOnly", el)
//         .text()
//         .trim();
//       const price = $(".unitLabel.pricingColumn span", el).text().trim();
//       const sqft = $(".unitLabel.sqftColumn span", el).text().trim();
//       const availability = $(
//         ".unitLabel.availableColumn span.dateAvailable",
//         el
//       )
//         .text()
//         .trim();
//
//       units.push({ unit, price, sqft, availability });
//     });
//
//     console.log(units);
//
//     const json2csvParser = new Parser();
//     const csv = json2csvParser.parse(units);
//
//     // Write CSV to a file
//     fs.writeFileSync("units.csv", csv);
//
//     // Send the file
//     res.download("units.csv");
//
//     // res.json({
//     //     units
//     // })
//   } catch (error) {
//     console.error(error);
//     res
//       .status(500)
//       .json({ error: "An error occurred while scraping the website" });
//   }
// });


app.post("/testing", (req, res) => {
  const filePath = path.join(__dirname, 'requestBody.json');

  // Convert the request body to a JSON string
  const data = JSON.stringify(req.body, null, 2);

  // Write the data to a new file
  fs.writeFile(filePath, data, (err) => {
    if (err) {
      console.error('Error writing file:', err);
      return res.status(500).send('Error writing file');
    }

    console.log('File has been saved.');
    res.send('File has been saved.');
  });
})

app.get("/puppeteer", async (req, res) => {
  try {
    // Launch the browser and open a new blank page
    // puppeteer.use(require('puppeteer-extra-plugin-stealth')())
    const browser = await puppeteer.launch({
      args: ["--no-sandbox"],
      args: ["--disable-http2"],
      headless: true,
    });
    const page = await browser.newPage();

    // Navigate the page to a URL
    await page.goto(
      "https://www.apartmentfinder.com/Pennsylvania/Newtown-Square-Apartments/Madison-Ellis-Preserve-Apartments-fbjn3tr"
    );

    // await page.goto(
    //   "https://www.google.com"
    // );

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

app.get("/puppet-test", async (req, res) => {
  try {
    // Launch the browser and open a new blank page
    puppeteer.use(require("puppeteer-extra-plugin-stealth")());
    const browser = await puppeteer.launch({
      args: ["--no-sandbox"],

      // args: ["--disable-http2"],
      headless: true,
    });
    const page = await browser.newPage();

    // Navigate the page to a URL
    await page.goto(
      "https://www.apartmentfinder.com/Pennsylvania/Newtown-Square-Apartments/Madison-Ellis-Preserve-Apartments-fbjn3tr"
    );

    // await page.goto(
    //   "https://www.google.com"
    // );

    // Set screen size
    await page.setViewport({ width: 1080, height: 1024 });

    // Type into search box
    const html = await page.content();

    res.send(html);
    console.log(html);
  } catch (error) {
    console.error(error);
    res
      .status(500)
      .json({ error: "An error occurred while scraping the website" });
  }
});

app.use("/stealth", stealthRouter);

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
