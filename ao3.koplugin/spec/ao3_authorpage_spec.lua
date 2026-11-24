-- KOReader busted spec for the author page: its screen and its parsers.
--
-- From a KOReader checkout with this plugin symlinked into plugins/:
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_authorpage_spec.lua spec/unit/
--   ./kodev test --busted=--pattern=ao3_authorpage_spec front
--
-- The screen is built from the same widgets the device paints, so the strip's
-- segments and the rows the menu pages through are exercised for real.

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

    it("names the shelf in the native title bar", function()
        assert.are.equal("Fandoms", AuthorPage.tabTitle("dashboard"))
        assert.are.equal("Works", AuthorPage.tabTitle("works"))
        assert.are.equal("Series", AuthorPage.tabTitle("series"))
        assert.are.equal("Bookmarks", AuthorPage.tabTitle("bookmarks"))
    end)

    it("draws one pill holding four near-equal segments", function()
        local strip = AuthorPage.tabStrip("works", function() end, 570, 19)
        assert.are.equal(4, #strip.segments)
        -- A pill, inset to the gutter: it keeps the width it is given, and the
        -- radius is half its own height so the ends are true half-circles.
        local size = strip:getSize()
        assert.are.equal(570, size.w)
        assert.are.equal(math.floor(size.h / 2), strip.radius)
        -- The four segments plus three dividers fill the inside exactly.
        local total = 3 * strip.bordersize
        for _, segment in ipairs(strip.segments) do
            total = total + segment.dimen.w
        end
        assert.are.equal(size.w, total + 2 * strip.bordersize)
        local widest, narrowest = 0, 1000
        for _, segment in ipairs(strip.segments) do
            widest = math.max(widest, segment.dimen.w)
            narrowest = math.min(narrowest, segment.dimen.w)
        end
        -- Sub-pixel borders are rounded per segment, so the last one may take
        -- a couple of pixels; the segments never differ by more than that.
        assert.is_true(widest - narrowest <= 4)
        assert.are.equal("dashboard", strip.segments[1].tab_id)
        assert.are.equal("bookmarks", strip.segments[4].tab_id)
    end)

    it("separates the four options with three internal rules", function()
        local strip = AuthorPage.tabStrip("dashboard", function() end, 570, 19)
        -- Inside the pill, tap areas and rules alternate: four options need
        -- exactly three dividers, each one hairline wide and full height, so
        -- they read as one bar cut into four rather than four floating labels.
        local dividers = 0
        for _, child in ipairs(strip[1]) do
            if not child.tab_id then
                dividers = dividers + 1
                assert.are.equal(strip.bordersize, child.dimen.w)
                assert.are.equal(strip[1]:getSize().h, child.dimen.h)
            end
        end
        assert.are.equal(3, dividers)
    end)

    it("marks only the active tab with the checkmark", function()
        local strip = AuthorPage.tabStrip("series", function() end, 600, 19)
        local marked = {}
        for _, segment in ipairs(strip.segments) do
            -- The segment centres one label: tap area -> centre -> text.
            local label = segment[1][1].text
            if label:find("\u{2713}", 1, true) then
                marked[#marked + 1] = segment.tab_id
            end
        end
        assert.are.same({ "series" }, marked)
    end)

    it("reports the tapped tab", function()
        local selected
        local strip = AuthorPage.tabStrip("dashboard",
            function(id) selected = id end, 600, 19)
        strip.segments[3].onTap()
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

describe("AO3 author page screen", function()
    local function build(over)
        local o = {
            tab = "dashboard",
            name = "Kingsaxcul",
            data = { items = {} },
            width = 570,
            font_size = 19,
            on_tab = function() end,
            on_listing = function() end,
            on_page = function() end,
            work_row = function(work) return { text = work.title, role = "work" } end,
        }
        for key, value in pairs(over or {}) do o[key] = value end
        return AuthorPage.build(o)
    end

    local function row(rows, wanted)
        for _, entry in ipairs(rows) do
            if entry.role == wanted then return entry end
        end
    end

    -- A padded row is gutter + the block + gutter. The count label sits in a
    -- fixed-width container (so the menu cannot centre it); the empty sentence
    -- is the block itself.
    local function count_text(rows)
        return row(rows, "author_count").ao3_static[2][1][2].text
    end

    local function empty_text(rows)
        return row(rows, "author_empty").ao3_static[2][2].text
    end

    it("keeps the masthead and the strip on all four tabs", function()
        for _, tab in ipairs({ "dashboard", "works", "series", "bookmarks" }) do
            local rows = build{ tab = tab }
            assert.are.equal("author_identity", rows[1].role)
            assert.is_truthy(row(rows, "author_tabs").ao3_tabs)
        end
    end)

    it("spends no solid bar on the page, because the strip is its navigation", function()
        -- A bar above the strip would be a second control for the works list,
        -- which is already a tab, and it would have to vanish on Works and move
        -- every tab up with it. The account screen sets the precedent: a page
        -- that is a contents page needs no primary of its own.
        for _, tab in ipairs({ "dashboard", "works", "series", "bookmarks" }) do
            local rows = build{ tab = tab, data = { items = { {} }, count = "1" } }
            assert.is_nil(row(rows, "author_all_works"))
            for _, entry in ipairs(rows) do
                assert.is_nil(entry.ao3_panel)
            end
        end
    end)

    it("counts the shelf above its records, singular when there is one", function()
        local fandom = { { name = "Code Geass", url = "/u/1", count = "1" } }
        assert.are.equal("1 fandom", count_text(build{ data = { items = fandom } }))
        assert.are.equal("12 works", count_text(
            build{ tab = "works", data = { items = { {} }, count = "12" } }))
        assert.are.equal("1 bookmark", count_text(
            build{ tab = "bookmarks",
                data = { items = { { kind = "work" } }, count = "1" } }))
        assert.are.equal("2 series", count_text(
            build{ tab = "series", data = { items = { {} }, count = "2" } }))
    end)

    it("paints fandoms and series as index records and bookmarks as work cards", function()
        local fandoms = build{ data = { items = {
            { name = "Code Geass", url = "/users/x/works?fandom_id=1", count = "3" },
        } } }
        local fandom = row(fandoms, "author_fandom")
        assert.is_truthy(fandom.ao3_fandom)
        assert.are.equal("Code Geass", fandom.text)
        assert.are.equal("3 works", fandom.mandatory)
        local fandom_url
        fandoms = build{
            data = { items = { { name = "Code Geass", url = "/u?fandom_id=1", count = "3" } } },
            on_listing = function(url) fandom_url = url end,
        }
        row(fandoms, "author_fandom").action()
        assert.are.equal("/u?fandom_id=1", fandom_url)

        local series = row(build{ tab = "series", data = { items = {
            { title = "Coils AU", url = "/series/4164283", works = "1" },
        }, count = "1" } }, "author_series")
        assert.is_truthy(series.ao3_series)
        assert.are.equal("Coils AU", series.text)
        assert.are.equal("1 work", series.mandatory)

        -- A bookmarked work keeps the card the listings paint.
        local bookmark = row(build{ tab = "bookmarks", data = { items = {
            { id = "7", title = "A Bookmarked Work", kind = "work" },
        }, count = "1" } }, "work")
        assert.are.equal("A Bookmarked Work", bookmark.text)
        assert.is_nil(bookmark.ao3_fandom)
    end)

    it("says so quietly when a shelf is empty", function()
        local rows = build{ tab = "bookmarks" }
        assert.are.equal("No bookmarks.", empty_text(rows))
        -- No count line over an empty shelf, and nothing to tap.
        assert.is_nil(row(rows, "author_count"))
        assert.is_nil(row(rows, "work"))
    end)

    it("pages with AO3's own next and previous links", function()
        local paged
        local rows = build{
            tab = "works",
            data = { items = { { title = "A" } }, count = "12",
                next_url = "https://archiveofourown.org/users/x/works?page=2" },
            on_page = function(url) paged = url end,
        }
        row(rows, "author_next").action()
        assert.are.equal("https://archiveofourown.org/users/x/works?page=2", paged)
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
