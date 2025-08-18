-- main.lua — Legal-move version (no castling/en passant yet)
local S = 80 -- square size
local board = {}
local turn = "white" -- side to move
local selected = nil
local legalTargets = {}
local statusText = ""
local gameOver = false

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
local function isWhite(p) return p ~= " " and p:match("%u") ~= nil end
local function isBlack(p) return p ~= " " and p:match("%l") ~= nil end
local function colorOf(p)
  if p==" " then return nil end
  return isWhite(p) and "white" or "black"
end
local function opp(side) return (side=="white") and "black" or "white" end

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

-- ===== PSEUDOLEGAL TARGETS (no king-safety) =====
local function targetsFor(b, r, c)
  local piece = b[r][c]
  if piece==" " then return {} end
  local side = colorOf(piece)
  local t = {}

  local function add(rr,cc, captureOnly, emptyOnly)
    if not inBounds(rr,cc) then return end
    local dest = b[rr][cc]
    if captureOnly then
      if dest~=" " and colorOf(dest) ~= side then table.insert(t, {r=rr,c=cc}) end
    elseif emptyOnly then
      if dest==" " then table.insert(t, {r=rr,c=cc}) end
    else
      if dest==" " or colorOf(dest) ~= side then table.insert(t, {r=rr,c=cc}) end
    end
  end

  local lower = piece:lower()

  if lower == "p" then
    local d = dirForPawn(side)
    -- one / two forward
    add(r+d, c, false, true)
    if r == startRankForPawn(side) and inBounds(r+d,c) and b[r+d][c]==" " then
      add(r+2*d, c, false, true)
    end
    -- captures
    add(r+d, c-1, true, false)
    add(r+d, c+1, true, false)
    -- (no en passant yet)
  elseif lower == "n" then
    local jumps = {{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
    for _,d in ipairs(jumps) do add(r+d[1], c+d[2]) end
  elseif lower == "k" then
    for dr=-1,1 do
      for dc=-1,1 do
        if not (dr==0 and dc==0) then add(r+dr,c+dc) end
      end
    end
    -- (no castling yet)
  elseif lower=="b" or lower=="r" or lower=="q" then
    for _,d in ipairs(slideDirections(piece)) do
      local rr,cc = r+d[1], c+d[2]
      while inBounds(rr,cc) do
        local dest = b[rr][cc]
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

-- ===== MOVE APPLY (includes auto-queen promotion) =====
local function doMove(b, fromR,fromC, toR,toC)
  local nb = cloneBoard(b)
  local piece = nb[fromR][fromC]
  nb[fromR][fromC] = " "
  if piece:lower()=="p" and toR == lastRankForPawn(colorOf(piece)) then
    nb[toR][toC] = isWhite(piece) and "Q" or "q"
  else
    nb[toR][toC] = piece
  end
  return nb
end

-- ===== KING SAFETY =====
local function findKing(b, side)
  local want = (side=="white") and "K" or "k"
  for r=1,8 do
    for c=1,8 do
      if b[r][c] == want then return r,c end
    end
  end
  return nil,nil
end

local function squareAttackedBy(b, r, c, attacker)
  -- pawns
  local d = dirForPawn(attacker)
  local pr1, pc1 = r - d, c - 1 -- inverse because we check "from attacker towards (r,c)"
  local pr2, pc2 = r - d, c + 1
  if inBounds(pr1,pc1) then
    local p = b[pr1][pc1]
    if attacker=="white" and p=="P" then return true end
    if attacker=="black" and p=="p" then return true end
  end
  if inBounds(pr2,pc2) then
    local p = b[pr2][pc2]
    if attacker=="white" and p=="P" then return true end
    if attacker=="black" and p=="p" then return true end
  end

  -- knights
  local jumps={{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
  for _,d2 in ipairs(jumps) do
    local rr,cc = r+d2[1], c+d2[2]
    if inBounds(rr,cc) then
      local p = b[rr][cc]
      if attacker=="white" and p=="N" then return true end
      if attacker=="black" and p=="n" then return true end
    end
  end

  -- king
  for dr=-1,1 do
    for dc=-1,1 do
      if not (dr==0 and dc==0) then
        local rr,cc=r+dr,c+dc
        if inBounds(rr,cc) then
          local p = b[rr][cc]
          if attacker=="white" and p=="K" then return true end
          if attacker=="black" and p=="k" then return true end
        end
      end
    end
  end

  -- bishops/rooks/queen (sliders)
  local function ray(drs, dcs, chars)
    local rr,cc = r+drs, c+dcs
    while inBounds(rr,cc) do
      local p = b[rr][cc]
      if p ~= " " then
        if attacker=="white" and isWhite(p) and chars[p] then return true end
        if attacker=="black" and isBlack(p) and chars[p] then return true end
        break
      end
      rr,cc = rr+drs, cc+dcs
    end
    return false
  end

  -- diagonals: B/Q
  if ray(-1,-1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray(-1, 1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray( 1,-1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray( 1, 1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  -- orthogonals: R/Q
  if ray(-1, 0, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 1, 0, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 0,-1, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 0, 1, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end

  return false
end

local function inCheck(b, side)
  local kr, kc = findKing(b, side)
  if not kr then return false end
  return squareAttackedBy(b, kr, kc, opp(side))
end

-- ===== LEGAL MOVE FILTER =====
local function legalTargetsFor(b, r, c)
  local piece = b[r][c]
  if piece==" " then return {} end
  local side = colorOf(piece)
  if side ~= turn then return {} end

  local out = {}
  local pseudo = targetsFor(b, r, c)
  for _,m in ipairs(pseudo) do
    local nb = doMove(b, r, c, m.r, m.c)
    if not inCheck(nb, side) then
      table.insert(out, m)
    end
  end
  return out
end

local function anyLegalMove(b, side)
  for r=1,8 do
    for c=1,8 do
      local p = b[r][c]
      if p ~= " " and colorOf(p)==side then
        local l = {}
        -- we need legal moves from perspective 'side', not global 'turn'
        local pseudo = targetsFor(b, r, c)
        for _,m in ipairs(pseudo) do
          local nb = doMove(b, r, c, m.r, m.c)
          if not inCheck(nb, side) then return true end
        end
      end
    end
  end
  return false
end

local function updateStatus()
  if gameOver then return end
  local side = turn
  local check = inCheck(board, side)
  local hasMove = anyLegalMove(board, side)
  if not hasMove and check then
    statusText = (side=="white" and "White" or "Black") .. " is checkmated!"
    gameOver = true
  elseif not hasMove then
    statusText = "Stalemate!"
    gameOver = true
  elseif check then
    statusText = (side=="white" and "White" or "Black") .. " is in check."
  else
    statusText = ""
  end
end

-- ===== UI helpers =====
local function coordsToSquare(x,y)
  local c = math.floor(x / S) + 1
  local r = math.floor(y / S) + 1
  if inBounds(r,c) then return r,c end
  return nil,nil
end

local function findInTargets(list, r,c)
  for _,m in ipairs(list) do if m.r==r and m.c==c then return true end end
  return false
end

-- ===== LOVE callbacks =====
function love.load()
  for r=1,8 do
    board[r] = {}
    for c=1,8 do board[r][c] = startpos[r][c] end
  end
  love.window.setMode(S*8, S*8)
  love.window.setTitle("Lua + LÖVE Chess — legal moves")
  updateStatus()
end

function love.draw()
  -- board
  for r=1,8 do
    for c=1,8 do
      if (r+c)%2==0 then love.graphics.setColor(0.9,0.9,0.9) else love.graphics.setColor(0.25,0.45,0.25) end
      love.graphics.rectangle("fill", (c-1)*S, (r-1)*S, S, S)
    end
  end

  -- selection
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

  -- HUD
  love.graphics.setColor(0,0,0)
  love.graphics.print("Turn: "..turn, 8, 8)
  if statusText ~= "" then
    love.graphics.print(statusText, 8, 28)
  end
  if gameOver then
    love.graphics.print("Game Over — press R to restart", 8, 48)
  end
end

function love.keypressed(key)
  if key=="r" then
    -- restart
    for r=1,8 do for c=1,8 do board[r][c]=startpos[r][c] end end
    turn, selected, legalTargets, gameOver, statusText = "white", nil, {}, false, ""
    updateStatus()
  end
end

function love.mousepressed(x,y,button)
  if button ~= 1 or gameOver then return end
  local r,c = coordsToSquare(x,y)
  if not r then return end

  if not selected then
    local p = board[r][c]
    if p ~= " " and colorOf(p)==turn then
      selected = {r=r,c=c}
      legalTargets = legalTargetsFor(board, r, c)
    end
  else
    local can = findInTargets(legalTargets, r, c)
    if can then
      board = doMove(board, selected.r, selected.c, r, c)
      turn = opp(turn)
      selected, legalTargets = nil, {}
      updateStatus()
    else
      local p = board[r][c]
      if p ~= " " and colorOf(p)==turn then
        selected = {r=r,c=c}
        legalTargets = legalTargetsFor(board, r, c)
        return
      end
      selected, legalTargets = nil, {}
    end
  end
end
