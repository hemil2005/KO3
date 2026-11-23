-- KOReader busted spec for the author page tab strip.
--
-- From a KOReader checkout with this plugin symlinked into plugins/:
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_authorpage_spec.lua spec/unit/
--   ./kodev test --busted=--pattern=ao3_authorpage_spec front
--
-- The strip uses native Button widgets, so this exercises the same widget
-- code the device paints.

require("commonrequire")

local AuthorPage = dofile("plugins/ao3.koplugin/authorpage.lua")

describe("AO3 author page tabs", function()
    it("lists the dashboard first, then works, series and bookmarks", function()
        local labels = {}
        for _, tab in ipairs(AuthorPage.TABS) do
            labels[#labels + 1] = tab.label
        end
        assert.are.same({ "Dashboard", "Works", "Series", "Bookmarks" }, labels)
    end)

    it("builds one horizontal row of buttons, none of them focusable", function()
        local strip = AuthorPage.tabStrip("works", function() end, 600)
        assert.are.equal(4, #strip)
        for _, button in ipairs(strip) do
            assert.is_false(button.focusable)
            assert.are.equal(150, button.width)
        end
    end)

    it("checks only the active tab", function()
        local strip = AuthorPage.tabStrip("series", function() end, 600)
        local checked = {}
        for _, button in ipairs(strip) do
            if button.checked_func() then
                checked[#checked + 1] = button.text
            end
        end
        assert.are.same({ "Series" }, checked)
    end)

    it("reports the tapped tab", function()
        local selected
        local strip = AuthorPage.tabStrip("dashboard", function(id) selected = id end, 600)
        strip[3].callback()
        assert.are.equal("series", selected)
    end)

    it("builds tab URLs from a profile or an existing sub-page", function()
        local base = "https://archiveofourown.org/users/foo/pseuds/bar"
        assert.are.equal(base .. "/works", AuthorPage.tabUrl(base, "works"))
        assert.are.equal(base .. "/works", AuthorPage.tabUrl(base .. "/works", "works"))
        assert.are.equal(base .. "/works", AuthorPage.tabUrl(base, "dashboard"))
        assert.are.equal(base .. "/series", AuthorPage.tabUrl(base .. "/series/", "series"))
        assert.are.equal(base .. "/bookmarks", AuthorPage.tabUrl(base, "bookmarks"))
        assert.is_nil(AuthorPage.tabUrl(nil, "works"))
        assert.is_nil(AuthorPage.tabUrl(base, "nope"))
    end)
end)

describe("AO3 author page parsers", function()
    local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/author/"

    local function read_fixture(name)
        local f = assert(io.open(fixture_dir .. name, "rb"))
        local body = f:read("*a")
        f:close()
        return body
    end

    it("lists the author's fandoms with counts and drill-down links", function()
        local page = assert(AuthorPage.parseFandoms(read_fixture("dashboard.html")))
        assert.are.equal(6, #page.items)
        assert.are.equal("Harry Potter - J. K. Rowling", page.items[1].name)
        assert.are.equal("/users/Kingsaxcul/works?fandom_id=136512", page.items[1].url)
        assert.are.equal("12", page.items[1].count)
        for _, item in ipairs(page.items) do
            assert.is_truthy(item.url:find("fandom_id=", 1, true))
        end
    end)

    it("returns an empty dashboard for a page without a fandom list", function()
        local page = assert(AuthorPage.parseFandoms(read_fixture("works.html")))
        assert.are.equal(0, #page.items)
    end)

    it("parses a series list with its stats", function()
        local page = assert(AuthorPage.parseSeries(read_fixture("series.html")))
        assert.are.equal(1, #page.items)
        local series = page.items[1]
        assert.are.equal("Coils AU", series.title)
        assert.are.equal("/series/4164283", series.url)
        assert.are.equal("2", series.works)
        assert.are.equal("147,683", series.words)
        assert.are.equal("14", series.bookmarks)
        assert.are.equal("23 Nov 2026", series.updated)
        assert.are.equal("2", page.count)
    end)

    it("parses work bookmarks as the bookmarked works", function()
        local page = assert(AuthorPage.parseBookmarks(read_fixture("bookmarks.html")))
        assert.are.equal(1, #page.items)
        local item = page.items[1]
        assert.are.equal("work", item.kind)
        assert.are.equal("52381945", item.id)
        assert.are.equal("Seat_Admiral", item.authors)
        assert.is_truthy(item.title:find("Coffin", 1, true))
        assert.is_truthy(item.summary:find("Roboute Guilliman dies", 1, true))
        assert.are.equal("1", page.count)
    end)

    it("parses series bookmarks as series entries", function()
        local html = [[
          <h2 class="heading">2 Bookmarks by Someone</h2>
          <li id="bookmark_42" class="bookmark blurb group series-4164283 user-1" role="article">
            <div class="header module">
              <h4 class="heading">
                <a href="/series/4164283">Coils AU</a> by
                <a rel="author" href="/users/Kingsaxcul/pseuds/Kingsaxcul">Kingsaxcul</a>
              </h4>
              <p class="datetime">23 Nov 2026</p>
            </div>
            <dl class="stats"><dt class="works">Works:</dt><dd class="works">2</dd></dl>
          </li>
        ]]
        local page = assert(AuthorPage.parseBookmarks(html))
        assert.are.equal(1, #page.items)
        assert.are.equal("series", page.items[1].kind)
        assert.are.equal("4164283", page.items[1].id)
        assert.are.equal("Coils AU", page.items[1].title)
        assert.are.equal("2", page.count)
    end)

    it("reads pagy and legacy pagination", function()
        local htmlparser = require("htmlparser")
        local pagy = AuthorPage.pagination(assert(htmlparser.parse([[
          <ol class="pagination actions pagy">
            <li class="prev"><a rel="prev" href="/users/X/series?page=1">Prev</a></li>
            <li class="next"><a rel="next" href="/users/X/series?page=3">Next</a></li>
          </ol>]])))
        assert.are.equal("https://archiveofourown.org/users/X/series?page=3", pagy.next_url)
        assert.are.equal("https://archiveofourown.org/users/X/series?page=1", pagy.prev_url)
        local legacy = AuthorPage.pagination(assert(htmlparser.parse([[
          <ol class="pagination actions">
            <li class="next"><a rel="next" href="/users/X/series?page=2">Next</a></li>
          </ol>]])))
        assert.are.equal("https://archiveofourown.org/users/X/series?page=2", legacy.next_url)
        assert.is_nil(legacy.prev_url)
    end)
end)

describe("AO3 downloaded-work TOC", function()
    local AuthorPage = dofile("plugins/ao3.koplugin/authorpage.lua")

    it("drops the Preface and the work-title wrapper, keeping chapters", function()
        local toc = {
            { title = "Preface", depth = 0, page = 1 },
            { title = "The Evans Boy", depth = 0, page = 1 },
            { title = "Chapter 1: Halloween, 1977", depth = 1, page = 2 },
            { title = "Chapter 2: The Letter", depth = 1, page = 9 },
            { title = "Afterword", depth = 1, page = 40 },
        }
        local cleaned = AuthorPage.cleanToc(toc)
        assert.are.equal(3, #cleaned)
        assert.are.equal("Chapter 1: Halloween, 1977", cleaned[1].title)
        assert.are.equal("Chapter 2: The Letter", cleaned[2].title)
        assert.are.equal("Afterword", cleaned[3].title)
        for _, item in ipairs(cleaned) do
            assert.are.equal(0, item.depth)
        end
        -- Pages are kept, so chapter navigation still lands correctly.
        assert.are.equal(2, cleaned[1].page)
        -- The input is not modified: ReaderToc caches what it is given.
        assert.are.equal(5, #toc)
        assert.are.equal(1, toc[3].depth)
    end)

    it("drops a Preface that crengine reports as a dash", function()
        local cleaned = AuthorPage.cleanToc({
            { title = "-", depth = 0, page = 1 },
            { title = "A Work", depth = 0, page = 3 },
            { title = "Chapter 1", depth = 1, page = 5 },
            { title = "INT. A ROOM — NIGHT", depth = 1, page = 5 },
        })
        assert.are.equal(2, #cleaned)
        assert.are.equal("Chapter 1", cleaned[1].title)
        assert.are.equal("INT. A ROOM — NIGHT", cleaned[2].title)
    end)

    it("drops an empty Preface entry too", function()
        local cleaned = AuthorPage.cleanToc({
            { title = "", depth = 0, page = 1 },
            { title = "A Work", depth = 0, page = 1 },
            { title = "Chapter 1", depth = 1, page = 2 },
        })
        assert.are.equal(1, #cleaned)
        assert.are.equal("Chapter 1", cleaned[1].title)
    end)

    it("keeps a one-chapter work's title as its only entry", function()
        local cleaned = AuthorPage.cleanToc({
            { title = "Preface", depth = 0, page = 1 },
            { title = "Blood and Chrome", depth = 0, page = 1 },
        })
        assert.are.equal(1, #cleaned)
        assert.are.equal("Blood and Chrome", cleaned[1].title)
        assert.are.equal(0, cleaned[1].depth)
    end)

    it("leaves an already flat TOC flat", function()
        local cleaned = AuthorPage.cleanToc({
            { title = "Chapter 1", depth = 0, page = 1 },
            { title = "Chapter 2", depth = 0, page = 4 },
        })
        assert.are.equal(2, #cleaned)
        assert.are.equal("Chapter 1", cleaned[1].title)
    end)

    it("handles an empty or missing TOC", function()
        assert.are.same({}, AuthorPage.cleanToc({}))
        assert.is_nil(AuthorPage.cleanToc(nil))
    end)
end)
