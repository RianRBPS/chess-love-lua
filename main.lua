-- main.lua
local S = 80 -- square size
local board = {}
local turn = "white" -- "white" or "black"
local selected = nil
local legalTargets = {}

-- start position (top = black, bottom = white)
local startpos = {
  {"r","n","b","q","k","b","n","r"},
  {"p","p","p","p","p","p","p","p"},
  {" "," "," "," "," "," "," "," "},
  {" "," "," "," "," "," "," "," "},
  {" "," "," "," "," "," "," "," "},
  {" "," "," "," "," "," "," "," "},
  {"P","P","P","P","P","P","P","P"},
  {"R","N","B","Q","K","B","N","R"},
}

local function cloneBoard(b)
  local nb = {}
  for r=1,8 do
    nb[r] = {}
    for c=1,8 do nb[r][c] = b[r][c] end
  end
  return nb
end

local function inBounds(r,c) return r>=1 and r<=8 and c>=1 and c<=8 end
local function isWhite(p) return p:match("%u") ~= nil end
local function isBlack(p) return p:match("%l") ~= nil end
local function colorOf(p)
  if p==" " then return nil end
  return isWhite(p) and "white" or "black"
end

local function dirForPawn(color) return (color=="white") and -1 or 1 end
local function startRankForPawn(color) return (color=="white") and 7 or 2 end
local function lastRankForPawn(color) return (color=="white") and 1 or 8 end

-- Sliding helper for B/R/Q
local function slideDirections(ch)
  if ch=="B" or ch=="b" then
    return {{-1,-1},{-1,1},{1,-1},{1,1}}
  elseif ch=="R" or ch=="r" then
    return {{-1,0},{1,0},{0,-1},{0,1}}
  elseif ch=="Q" or ch=="q" then
    return {{-1,-1},{-1,1},{1,-1},{1,1},{-1,0},{1,0},{0,-1},{0,1}}
  else
    return {}
  end
end

-- Generate pseudolegal targets for a piece at (r,c)
local function targetsFor(board, r, c)
  local piece = board[r][c]
  if piece==" " then return {} end
  local side = colorOf(piece)
  local t = {}

  local function addIfValid(rr,cc, captureOnly, emptyOnly)
    if not inBounds(rr,cc) then return end
    local dest = board[rr][cc]
    if captureOnly then
      if dest~=" " and colorOf(dest) ~= side then
        table.insert(t, {r=rr,c=cc})
      end
    elseif emptyOnly then
      if dest==" " then
        table.insert(t, {r=rr,c=cc})
      end
    else
      if dest==" " or colorOf(dest) ~= side then
        table.insert(t, {r=rr,c=cc})
      end
    end
  end

  local p = piece
  local lower = p:lower()

  if lower == "p" then
    local d = dirForPawn(side)
    -- one step
    addIfValid(r+d, c, false, true)
    -- two steps from start if clear
    if r == startRankForPawn(side) and board[r+d][c]==" " then
      addIfValid(r+2*d, c, false, true)
    end
    -- captures
    addIfValid(r+d, c-1, true, false)
    addIfValid(r+d, c+1, true, false)
    -- (no en passant yet)
  elseif lower == "n" then
    local jumps = {{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
    for _,d in ipairs(jumps) do addIfValid(r+d[1], c+d[2]) end
  elseif lower == "k" then
    for dr=-1,1 do
      for dc=-1,1 do
        if not (dr==0 and dc==0) then addIfValid(r+dr,c+dc) end
      end
    end
    -- (no castling yet)
  elseif lower=="b" or lower=="r" or lower=="q" then
    for _,d in ipairs(slideDirections(p)) do
      local rr,cc = r+d[1], c+d[2]
      while inBounds(rr,cc) do
        local dest = board[rr][cc]
        if dest==" " then
          table.insert(t,{r=rr,c=cc})
        else
          if colorOf(dest) ~= side then table.insert(t,{r=rr,c=cc}) end
          break
        end
        rr,cc = rr + d[1], cc + d[2]
      end
    end
  end

  return t
end

local function coordsToSquare(x,y)
  local c = math.floor(x / S) + 1
  local r = math.floor(y / S) + 1
  if inBounds(r,c) then return r,c end
  return nil,nil
end

local function isSameSquare(a,b) return a and b and a.r==b.r and a.c==b.c end

local function findInTargets(list, r,c)
  for _,m in ipairs(list) do if m.r==r and m.c==c then return true end end
  return false
end

local function doMove(b, fromR,fromC, toR,toC)
  local nb = cloneBoard(b)
  local piece = nb[fromR][fromC]
  nb[fromR][fromC] = " "
  -- promotion (auto-queen)
  if piece:lower()=="p" and toR == lastRankForPawn(colorOf(piece)) then
    nb[toR][toC] = (isWhite(piece) and "Q" or "q")
  else
    nb[toR][toC] = piece
  end
  return nb
end

function love.load()
  for r=1,8 do
    board[r] = {}
    for c=1,8 do board[r][c] = startpos[r][c] end
  end
  love.window.setMode(S*8, S*8)
  love.window.setTitle("Lua + LÖVE Chess — pseudolegal moves")
end

function love.draw()
  -- board squares
  for r=1,8 do
    for c=1,8 do
      if (r+c)%2==0 then love.graphics.setColor(0.9,0.9,0.9) else love.graphics.setColor(0.25,0.45,0.25) end
      love.graphics.rectangle("fill", (c-1)*S, (r-1)*S, S, S)
    end
  end

  -- selection highlight
  if selected then
    love.graphics.setColor(1,1,0,0.35)
    love.graphics.rectangle("fill", (selected.c-1)*S, (selected.r-1)*S, S, S)
  end

  -- legal target dots
  for _,m in ipairs(legalTargets) do
    love.graphics.setColor(0,0,0,0.35)
    love.graphics.circle("fill", (m.c-0.5)*S, (m.r-0.5)*S, S*0.15)
  end

  -- pieces
  for r=1,8 do
    for c=1,8 do
      local piece = board[r][c]
      if piece ~= " " then
        love.graphics.setColor(0,0,0)
        love.graphics.printf(piece, (c-1)*S, (r-1)*S + S/3, S, "center")
      end
    end
  end

  -- turn text
  love.graphics.setColor(0,0,0)
  love.graphics.print("Turn: "..turn, 8, 8)
end

function love.mousepressed(x,y,button)
  if button ~= 1 then return end
  local r,c = coordsToSquare(x,y)
  if not r then return end

  if not selected then
    -- select if it's your own piece
    local p = board[r][c]
    if p ~= " " and colorOf(p)==turn then
      selected = {r=r,c=c}
      legalTargets = targetsFor(board, r, c)
    end
  else
    -- second click: move if legal target
    local can = findInTargets(legalTargets, r, c)
    if can then
      board = doMove(board, selected.r, selected.c, r, c)
      turn = (turn=="white") and "black" or "white"
    else
      -- reselect if clicked on your own piece, otherwise clear
      local p = board[r][c]
      if p ~= " " and colorOf(p)==turn then
        selected = {r=r,c=c}
        legalTargets = targetsFor(board, r, c)
        return
      end
    end
    selected = nil
    legalTargets = {}
  end
end
