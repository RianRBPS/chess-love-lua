local S = 80 -- square size

-- ======= AI SETTINGS =======
local AI_ENABLED   = true      -- set true to play vs AI (AI plays Black)
local AI_SIDE      = "black"
local AI_TIME_MS   = 3500   -- time per move in milliseconds (increase for stronger play)
local AI_MAX_DEPTH = 6         -- safety cap (iterative deepening will stop earlier if time ends)

-- ======= GAME STATE =======
local board = {}
local state = {                 -- extra rule state
  castle = { wK=true, wQ=true, bK=true, bQ=true }, -- K-side / Q-side
  enpassant = nil,              -- {r=..., c=...} or nil (target square)
}
local turn = "white"
local selected = nil
local legalTargets = {}
local statusText = ""
local gameOver = false

-- promotion UI state: when set, blocks board input until a choice is made
-- { fromR, fromC, toR, toC, side }
local promoting = nil

-- sprites (loaded if PNGs exist)
local sprites = {} -- e.g., sprites["wP"] = Image, sprites["bQ"]=Image

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

-- ======= UTILS =======
local function cloneBoard(b)
  local nb = {}
  for r=1,8 do
    nb[r] = {}
    for c=1,8 do nb[r][c] = b[r][c] end
  end
  return nb
end

local function cloneState(s)
  return {
    enpassant = s.enpassant and { r=s.enpassant.r, c=s.enpassant.c } or nil,
    castle = {
      wK = s.castle.wK, wQ = s.castle.wQ,
      bK = s.castle.bK, bQ = s.castle.bQ
    }
  }
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

local function pieceKeyFromChar(ch)
  if ch==" " then return nil end
  local side = isWhite(ch) and "w" or "b"
  local t = ch:upper()
  return side .. t -- e.g., "wP", "bQ"
end

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

-- ======= SPRITES =======
local function tryLoad(imgPath)
  local ok, img = pcall(love.graphics.newImage, imgPath)
  if ok then return img end
  return nil
end

local function loadSprites()
  local names = {"P","R","N","B","Q","K"}
  for _,n in ipairs(names) do
    sprites["w"..n] = tryLoad("assets/w"..n..".png")
    sprites["b"..n] = tryLoad("assets/b"..n..".png")
  end
end

local function drawPiece(piece, x, y)
  local key = pieceKeyFromChar(piece)
  local img = key and sprites[key] or nil
  if img then
    local iw, ih = img:getWidth(), img:getHeight()
    local scale = math.min(S/iw, S/ih)
    local offx = (S - iw*scale) / 2
    local offy = (S - ih*scale) / 2
    love.graphics.setColor(1,1,1)
    love.graphics.draw(img, x+offx, y+offy, 0, scale, scale)
  else
    love.graphics.setColor(0,0,0)
    love.graphics.printf(piece, x, y + S/3, S, "center")
  end
end

-- ======= ATTACK / CHECK =======
local function squareAttackedBy(b, r, c, attacker)
  -- pawns (note reversed perspective for detection)
  local d = dirForPawn(attacker)
  for _,dc in ipairs({-1,1}) do
    local rr,cc = r - d, c - dc
    if inBounds(rr,cc) then
      local p = b[rr][cc]
      if attacker=="white" and p=="P" then return true end
      if attacker=="black" and p=="p" then return true end
    end
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

  -- sliders: bishops/rooks/queen
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
  -- diagonals (B/Q)
  if ray(-1,-1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray(-1, 1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray( 1,-1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  if ray( 1, 1, attacker=="white" and {B=true,Q=true} or {b=true,q=true}) then return true end
  -- orthogonals (R/Q)
  if ray(-1, 0, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 1, 0, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 0,-1, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end
  if ray( 0, 1, attacker=="white" and {R=true,Q=true} or {r=true,q=true}) then return true end

  return false
end

local function findKing(b, side)
  local want = (side=="white") and "K" or "k"
  for r=1,8 do
    for c=1,8 do
      if b[r][c] == want then return r,c end
    end
  end
  return nil,nil
end

local function inCheck(b, side)
  local kr, kc = findKing(b, side)
  if not kr then return false end
  return squareAttackedBy(b, kr, kc, opp(side))
end

-- ======= MOVE GEN (PSEUDO, incl. promo flags, castle, en passant) =======
-- Returns list of moves { r=toR, c=toC, castle="K"/"Q"|nil, enpassant=true|nil, promote=true|nil }
local function targetsFor(b, r, c, st)
  local piece = b[r][c]
  if piece==" " then return {} end
  local side = colorOf(piece)
  local t = {}

  local function add(rr,cc, captureOnly, emptyOnly, flags)
    if not inBounds(rr,cc) then return end
    local dest = b[rr][cc]
    local f = {}
    if flags then for k,v in pairs(flags) do f[k]=v end end

    local willPromote = (piece:lower()=="p" and rr == lastRankForPawn(side))
    if willPromote then f.promote = true end

    if captureOnly then
      if dest~=" " and colorOf(dest) ~= side then
        table.insert(t, {r=rr,c=cc, castle=f.castle, enpassant=f.enpassant, promote=f.promote})
      end
    elseif emptyOnly then
      if dest==" " then
        table.insert(t, {r=rr,c=cc, castle=f.castle, enpassant=f.enpassant, promote=f.promote})
      end
    else
      if dest==" " or colorOf(dest) ~= side then
        table.insert(t, {r=rr,c=cc, castle=f.castle, enpassant=f.enpassant, promote=f.promote})
      end
    end
  end

  local lower = piece:lower()

  if lower == "p" then
    local d = dirForPawn(side)
    -- forward
    if inBounds(r+d,c) and b[r+d][c]==" " then
      add(r+d, c, false, true)
      if r == startRankForPawn(side) and b[r+2*d] and b[r+2*d][c]==" " then
        add(r+2*d, c, false, true) -- two-step
      end
    end
    -- captures
    add(r+d, c-1, true, false)
    add(r+d, c+1, true, false)
    -- en passant
    if st.enpassant then
      for _,dc in ipairs({-1,1}) do
        local er,ec = r+d, c+dc
        if er==st.enpassant.r and ec==st.enpassant.c and b[er][ec]==" " then
          add(er, ec, false, false, { enpassant = true })
        end
      end
    end

  elseif lower == "n" then
    local jumps = {{-2,-1},{-2,1},{-1,-2},{-1,2},{1,-2},{1,2},{2,-1},{2,1}}
    for _,d in ipairs(jumps) do add(r+d[1], c+d[2]) end

  elseif lower == "k" then
    -- normal king steps
    for dr=-1,1 do
      for dc=-1,1 do
        if not (dr==0 and dc==0) then add(r+dr,c+dc) end
      end
    end
    -- castling (check squares not attacked & path empty & rights)
    if side=="white" and r==8 and c==5 then
      if st.castle.wK and b[8][6]==" " and b[8][7]==" " and b[8][8]:lower()=="r" then
        if not inCheck(b,"white")
           and not squareAttackedBy(b,8,6,"black")
           and not squareAttackedBy(b,8,7,"black") then
          add(8,7,false,false,{ castle="K" })
        end
      end
      if st.castle.wQ and b[8][4]==" " and b[8][3]==" " and b[8][2]==" " and b[8][1]:lower()=="r" then
        if not inCheck(b,"white")
           and not squareAttackedBy(b,8,4,"black")
           and not squareAttackedBy(b,8,3,"black") then
          add(8,3,false,false,{ castle="Q" })
        end
      end
    elseif side=="black" and r==1 and c==5 then
      if st.castle.bK and b[1][6]==" " and b[1][7]==" " and b[1][8]:lower()=="r" then
        if not inCheck(b,"black")
           and not squareAttackedBy(b,1,6,"white")
           and not squareAttackedBy(b,1,7,"white") then
          add(1,7,false,false,{ castle="K" })
        end
      end
      if st.castle.bQ and b[1][4]==" " and b[1][3]==" " and b[1][2]==" " and b[1][1]:lower()=="r" then
        if not inCheck(b,"black")
           and not squareAttackedBy(b,1,4,"white")
           and not squareAttackedBy(b,1,3,"white") then
          add(1,3,false,false,{ castle="Q" })
        end
      end
    end

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

-- ======= APPLY MOVE (PURE: returns nb, nstate) =======
-- move fields: r,c, and optional castle="K"/"Q", enpassant=true, promote=true, promoPiece="Q"/"R"/"B"/"N"
local function applyMove(b, fromR,fromC, move, st)
  local nb = cloneBoard(b)
  local ns = cloneState(st)

  local piece = nb[fromR][fromC]
  local side = colorOf(piece)
  local toR, toC = move.r, move.c
  nb[fromR][fromC] = " "

  -- en passant capture: remove pawn from original file
  if move.enpassant then
    nb[fromR][toC] = " "
  end

  -- castling: also move rook
  if move.castle == "K" then
    if side=="white" then
      nb[8][6] = nb[8][8]; nb[8][8] = " "
    else
      nb[1][6] = nb[1][8]; nb[1][8] = " "
    end
  elseif move.castle == "Q" then
    if side=="white" then
      nb[8][4] = nb[8][1]; nb[8][1] = " "
    else
      nb[1][4] = nb[1][1]; nb[1][1] = " "
    end
  end

  -- place moving piece (handle promotion)
  if piece:lower()=="p" and toR == lastRankForPawn(side) then
    local promoteTo = (move.promoPiece or "Q")
    nb[toR][toC] = (side=="white") and promoteTo or promoteTo:lower()
  else
    nb[toR][toC] = piece
  end

  -- ===== Update castling rights =====
  local function disableRights(forSide, which) -- which: "K","Q","both"
    if forSide=="white" then
      if which=="K" or which=="both" then ns.castle.wK=false end
      if which=="Q" or which=="both" then ns.castle.wQ=false end
    else
      if which=="K" or which=="both" then ns.castle.bK=false end
      if which=="Q" or which=="both" then ns.castle.bQ=false end
    end
  end

  if piece=="K" then disableRights("white","both") end
  if piece=="k" then disableRights("black","both") end

  if piece=="R" then
    if fromR==8 and fromC==8 then disableRights("white","K") end
    if fromR==8 and fromC==1 then disableRights("white","Q") end
  elseif piece=="r" then
    if fromR==1 and fromC==8 then disableRights("black","K") end
    if fromR==1 and fromC==1 then disableRights("black","Q") end
  end

  local captured = b[toR][toC]
  if captured=="R" then
    if toR==8 and toC==8 then disableRights("white","K") end
    if toR==8 and toC==1 then disableRights("white","Q") end
  elseif captured=="r" then
    if toR==1 and toC==8 then disableRights("black","K") end
    if toR==1 and toC==1 then disableRights("black","Q") end
  end

  if move.castle then
    disableRights(side,"both")
  end

  -- ===== Update en passant target =====
  ns.enpassant = nil
  if piece:lower()=="p" then
    local d = dirForPawn(side)
    if math.abs(toR - fromR) == 2 then
      ns.enpassant = { r = fromR + d, c = fromC }
    end
  end

  return nb, ns
end

-- ======= LEGAL FILTER =======
local function legalTargetsFor(b, r, c, st)
  local piece = b[r][c]
  if piece==" " then return {} end
  local side = colorOf(piece)
  if side ~= turn then return {} end

  local out = {}
  local pseudo = targetsFor(b, r, c, st)
  for _,m in ipairs(pseudo) do
    -- simulate with default queen promo to ensure king safety is tested
    local simMove = {}
    for k,v in pairs(m) do simMove[k]=v end
    if m.promote and not simMove.promoPiece then simMove.promoPiece = "Q" end
    local nb, ns = applyMove(b, r, c, simMove, st)
    if not inCheck(nb, side) then
      table.insert(out, m)
    end
  end
  return out
end

local function anyLegalMove(b, side, st)
  for r=1,8 do
    for c=1,8 do
      local p = b[r][c]
      if p ~= " " and colorOf(p)==side then
        local pseudo = targetsFor(b, r, c, st)
        for _,m in ipairs(pseudo) do
          local simMove = {}
          for k,v in pairs(m) do simMove[k]=v end
          if m.promote and not simMove.promoPiece then simMove.promoPiece = "Q" end
          local nb, ns = applyMove(b, r, c, simMove, st)
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
  local hasMove = anyLegalMove(board, side, state)
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

-- ======= UI helpers & LOVE callbacks =======
local function coordsToSquare(x,y)
  local c = math.floor(x / S) + 1
  local r = math.floor(y / S) + 1
  if inBounds(r,c) then return r,c end
  return nil,nil
end

local function findInTargets(list, r,c)
  for _,m in ipairs(list) do if m.r==r and m.c==c then return m end end
  return nil
end

local function startPosition()
  for r=1,8 do
    board[r] = {}
    for c=1,8 do board[r][c] = startpos[r][c] end
  end
  state = { castle = { wK=true,wQ=true,bK=true,bQ=true }, enpassant=nil }
  turn, selected, legalTargets, gameOver, statusText, promoting =
      "white", nil, {}, false, "", nil
end

function love.load()
  love.window.setMode(S*8, S*8)
  love.window.setTitle("Lua + LÖVE Chess — promotion UI + sprites")
  loadSprites()
  initZobrist()
  startPosition()
  updateStatus()
end

function love.keypressed(key)
  if key=="r" then startPosition(); updateStatus() end
end

-- Promotion modal layout
local function promotionButtons(side)
  -- Return a table of buttons {x,y,w,h,label,imgKey,pieceLetter}
  local W, H = 360, 120
  local cx = (S*8 - W)/2
  local cy = (S*8 - H)/2
  local opts = {"Q","R","B","N"}
  local btns = {}
  local bw, bh = 80, 80
  local pad = 10
  local x = cx + 10
  for i,lab in ipairs(opts) do
    local y = cy + (H - bh)/2
    table.insert(btns, {
      x=x, y=y, w=bw, h=bh,
      label=lab,
      imgKey=(side=="white" and "w"..lab or "b"..lab),
      pieceLetter=lab
    })
    x = x + bw + pad
  end
  return {x=cx,y=cy,w=W,h=H, btns=btns}
end

local function drawPromotionUI()
  if not promoting then return end
  local side = promoting.side
  local ui = promotionButtons(side)

  -- modal bg
  love.graphics.setColor(0,0,0,0.45)
  love.graphics.rectangle("fill", 0,0, S*8, S*8)

  -- panel
  love.graphics.setColor(0.95,0.95,0.95)
  love.graphics.rectangle("fill", ui.x, ui.y, ui.w, ui.h, 8,8)
  love.graphics.setColor(0,0,0)
  love.graphics.print("Choose promotion", ui.x+10, ui.y+8)

  -- buttons
  for _,b in ipairs(ui.btns) do
    love.graphics.setColor(0.85,0.85,0.85)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6,6)
    love.graphics.setColor(0,0,0)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6,6)
    -- icon or letter
    local img = sprites[b.imgKey]
    if img then
      local iw,ih = img:getWidth(), img:getHeight()
      local scale = math.min((b.w-10)/iw, (b.h-10)/ih)
      local offx = (b.w - iw*scale)/2
      local offy = (b.h - ih*scale)/2
      love.graphics.setColor(1,1,1)
      love.graphics.draw(img, b.x+offx, b.y+offy, 0, scale, scale)
    else
      love.graphics.setColor(0,0,0)
      love.graphics.printf(b.pieceLetter, b.x, b.y + b.h/3, b.w, "center")
    end
  end
end

local function clickPromotion(x,y)
  if not promoting then return false end
  local side = promoting.side
  local ui = promotionButtons(side)
  for _,b in ipairs(ui.btns) do
    if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
      -- apply chosen promotion
      local move = { r=promoting.toR, c=promoting.toC, promote=true, promoPiece=b.pieceLetter }
      board, state = applyMove(board, promoting.fromR, promoting.fromC, move, state)
      turn = opp(turn)
      promoting = nil
      updateStatus()
      return true
    end
  end
  return false
end

function love.draw()
  -- board
  for r=1,8 do
    for c=1,8 do
      if (r+c)%2==0 then love.graphics.setColor(0.9,0.9,0.9) else love.graphics.setColor(0.25,0.45,0.25) end
      love.graphics.rectangle("fill", (c-1)*S, (r-1)*S, S, S)
    end
  end

  -- selection and legal target dots (only when not promoting)
  if not promoting then
    if selected then
      love.graphics.setColor(1,1,0,0.35)
      love.graphics.rectangle("fill", (selected.c-1)*S, (selected.r-1)*S, S, S)
    end
    for _,m in ipairs(legalTargets) do
      love.graphics.setColor(0,0,0,0.35)
      love.graphics.circle("fill", (m.c-0.5)*S, (m.r-0.5)*S, S*0.15)
    end
  end

  -- pieces
  for r=1,8 do
    for c=1,8 do
      local piece = board[r][c]
      if piece ~= " " then
        drawPiece(piece, (c-1)*S, (r-1)*S)
      end
    end
  end

  -- HUD
  love.graphics.setColor(0,0,0)
  love.graphics.print("Turn: "..turn, 8, 8)
  if state.enpassant then
    love.graphics.print(("EP: %d,%d"):format(state.enpassant.r, state.enpassant.c), 8, 28)
  end
  if statusText ~= "" then
    love.graphics.print(statusText, 8, 48)
  end
  if gameOver then
    love.graphics.print("Game Over — press R to restart", 8, 68)
  end

  -- Promotion modal (on top)
  drawPromotionUI()
end

function love.mousepressed(x,y,button)
  if button ~= 1 or gameOver then return end

  -- promotion UI click has priority
  if promoting then
    if clickPromotion(x,y) then return end
    -- click outside does nothing
    return
  end

  local r,c = coordsToSquare(x,y)
  if not r then return end

  if not selected then
    local p = board[r][c]
    if p ~= " " and colorOf(p)==turn then
      selected = {r=r,c=c}
      legalTargets = legalTargetsFor(board, r, c, state)
    end
  else
    local m = findInTargets(legalTargets, r, c)
    if m then
      -- If this move promotes, open UI instead of applying now
      if m.promote then
        promoting = { fromR=selected.r, fromC=selected.c, toR=r, toC=c, side=turn }
        -- clear UI selection behind modal
        selected, legalTargets = nil, {}
        return
      end
      -- normal move
      board, state = applyMove(board, selected.r, selected.c, m, state)
      turn = opp(turn)
      selected, legalTargets = nil, {}
      updateStatus()
    else
      local p = board[r][c]
      if p ~= " " and colorOf(p)==turn then
        selected = {r=r,c=c}
        legalTargets = legalTargetsFor(board, r, c, state)
        return
      end
      selected, legalTargets = nil, {}
    end
  end
end

-- ======= ZOBRIST-LIKE HASH (simple) =======
local Z = {}

local bit = bit or require("bit")  -- LuaJIT bit operations

local function rand32()
  -- simple deterministic 32-bit-ish value for hashing
  local x = love.math.random(0, 0x7fffffff)
  return bit.bxor(x, bit.lshift(x, 16))
end


function initZobrist()
  local pieces = {"P","N","B","R","Q","K","p","n","b","r","q","k"}
  for _,pc in ipairs(pieces) do
    Z[pc] = {}
    for sq=1,64 do Z[pc][sq] = rand32() end
  end
  Z.turn = rand32()
end

local function hashBoard(b, sideToMove)
  local h = 0
  for r=1,8 do
    for c=1,8 do
      local p = b[r][c]
      if p ~= " " then
        local sq = (r-1)*8 + c
        h = bit.bxor(h, Z[p][sq])
      end
    end
  end
  if sideToMove == "white" then
    h = bit.bxor(h, Z.turn)
  end
  return h
end

-- ======= EVALUATION =======
local VAL = { P=100, N=320, B=330, R=500, Q=900, K=0 }
-- simple piece-square tables (white perspective; black uses mirrored)
local PST = {
  P = {
    { 0,  0,  0,  0,  0,  0,  0,  0},
    {50, 50, 50, 50, 50, 50, 50, 50},
    {10, 10, 20, 30, 30, 20, 10, 10},
    { 5,  5, 10, 25, 25, 10,  5,  5},
    { 0,  0,  0, 20, 20,  0,  0,  0},
    { 5, -5,-10,  0,  0,-10, -5,  5},
    { 5, 10, 10,-20,-20, 10, 10,  5},
    { 0,  0,  0,  0,  0,  0,  0,  0},
  },
  N = {
    {-50,-40,-30,-30,-30,-30,-40,-50},
    {-40,-20,  0,  0,  0,  0,-20,-40},
    {-30,  0, 10, 15, 15, 10,  0,-30},
    {-30,  5, 15, 20, 20, 15,  5,-30},
    {-30,  0, 15, 20, 20, 15,  0,-30},
    {-30,  5, 10, 15, 15, 10,  5,-30},
    {-40,-20,  0,  5,  5,  0,-20,-40},
    {-50,-40,-30,-30,-30,-30,-40,-50},
  },
  B = {
    {-20,-10,-10,-10,-10,-10,-10,-20},
    {-10,  0,  0,  0,  0,  0,  0,-10},
    {-10,  0,  5, 10, 10,  5,  0,-10},
    {-10,  5,  5, 10, 10,  5,  5,-10},
    {-10,  0, 10, 10, 10, 10,  0,-10},
    {-10, 10, 10, 10, 10, 10, 10,-10},
    {-10,  5,  0,  0,  0,  0,  5,-10},
    {-20,-10,-10,-10,-10,-10,-10,-20},
  },
  R = {
    { 0,  0,  0,  5,  5,  0,  0,  0},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    { 5, 10, 10, 10, 10, 10, 10,  5},
    { 0,  0,  0,  0,  0,  0,  0,  0},
  },
  Q = {
    {-20,-10,-10, -5, -5,-10,-10,-20},
    {-10,  0,  0,  0,  0,  0,  0,-10},
    {-10,  0,  5,  5,  5,  5,  0,-10},
    { -5,  0,  5,  5,  5,  5,  0, -5},
    {  0,  0,  5,  5,  5,  5,  0, -5},
    {-10,  5,  5,  5,  5,  5,  0,-10},
    {-10,  0,  5,  0,  0,  0,  0,-10},
    {-20,-10,-10, -5, -5,-10,-10,-20},
  },
  K = { -- middlegame-ish
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-30,-30,-40,-40,-30,-30,-30},
    {-30,-30,-30,-40,-40,-30,-30,-30},
    {-20,-20,-20,-20,-20,-20,-20,-20},
    {-10,-10,-10,-10,-10,-10,-10,-10},
    { 20, 20,  0,  0,  0,  0, 20, 20},
    { 20, 30, 10,  0,  0, 10, 30, 20},
  }
}

local function pstScore(piece, r, c)
  local up = piece:upper()
  local tbl = PST[up]
  if not tbl then return 0 end
  -- white tables are from white POV (row 1 top). Our board has r=1 at top for black,
  -- so we mirror for black pieces.
  if isWhite(piece) then
    return tbl[r][c]
  else
    return tbl[9-r][c]
  end
end

local function evaluate(board)
  -- positive = White better
  local score = 0
  local whiteMob, blackMob = 0, 0

  for r=1,8 do
    for c=1,8 do
      local p = board[r][c]
      if p ~= " " then
        local up = p:upper()
        local val = VAL[up] or 0
        local pst = pstScore(p, r, c)
        if isWhite(p) then score = score + val + pst else score = score - val - pst end
      end
    end
  end

  -- light mobility (optional, cheap): count pseudolegal moves
  local dummyState = { enpassant=nil, castle={wK=true,wQ=true,bK=true,bQ=true} } -- rough
  for r=1,8 do for c=1,8 do
    local p = board[r][c]
    if p ~= " " then
      local moves = targetsFor(board, r, c, dummyState)
      if isWhite(p) then whiteMob = whiteMob + #moves else blackMob = blackMob + #moves end
    end
  end end
  score = score + 2*(whiteMob - blackMob)

  -- king danger: in-check penalty to the side in check
  if inCheck(board, "white") then score = score - 30 end
  if inCheck(board, "black") then score = score + 30 end

  return score
end

-- ======= SEARCH (Alpha-Beta + Quiescence + TT + Iterative Deepening) =======
local INF = 1e9
local TT = {} -- transposition table: key -> {depth, score, flag, move}
-- flag: 0 = exact, -1 = alpha (lower bound), 1 = beta (upper bound)

local killers = {}   -- killers[depth] = { move1, move2 }
local nodes = 0
local startTime = 0
local timeLimit = 1000
local stopSearch = false

local function ms() return love.timer.getTime() * 1000 end

local function isTimeUp()
  if (ms() - startTime) >= timeLimit then
    stopSearch = true
    return true
  end
  return false
end

local function moveKey(m)
  -- compact key string for ordering/killers
  return string.format("%02d%02d%02d%02d%s%s",
    m.fromR or 0, m.fromC or 0, m.r, m.c, m.castle or "", m.enpassant and "e" or "")
end

local function orderMoves(board, state, side, moves, pvMove)
  -- captures first, then castle, then killers, then others
  local scored = {}
  for _,m in ipairs(moves) do
    local score = 0
    -- MVV-LVA style: check if destination had a capture
    -- we don't know from here; but we can peek original board:
    local dest = board[m.r][m.c]
    if dest ~= " " then
      local victim = VAL[dest:upper()] or 0
      score = score + 1000 + victim
    end
    if m.castle then score = score + 300 end
    if pvMove and m.r==pvMove.r and m.c==pvMove.c and m.fromR==pvMove.fromR and m.fromC==pvMove.fromC then
      score = score + 5000
    end
    -- killer moves bonus
    local mk = moveKey(m)
    local kd = killers[m.depth or 0]
    if kd then
      if kd[1] == mk then score = score + 800 end
      if kd[2] == mk then score = score + 700 end
    end
    table.insert(scored, {m=m, s=score})
  end
  table.sort(scored, function(a,b) return a.s > b.s end)
  local out = {}
  for _,e in ipairs(scored) do table.insert(out, e.m) end
  return out
end

local function quiescence(b, st, side, alpha, beta)
  nodes = nodes + 1
  if stopSearch or isTimeUp() then return evaluate(b) end

  local stand = evaluate(b)
  if stand >= beta then return beta end
  if stand > alpha then alpha = stand end

  -- only consider "noisy" moves (captures & promotions)
  for r=1,8 do for c=1,8 do
    local p = b[r][c]
    if p ~= " " and colorOf(p)==side then
      local pseudo = targetsFor(b, r, c, st)
      for _,m in ipairs(pseudo) do
        local isCapture = b[m.r][m.c] ~= " "
        local isPromo = m.promote
        if isCapture or isPromo then
          local sim = {}
          for k,v in pairs(m) do sim[k]=v end
          if isPromo and not sim.promoPiece then sim.promoPiece = "Q" end
          local nb, ns = applyMove(b, r, c, sim, st)
          if not inCheck(nb, side) then
            local score = -quiescence(nb, ns, opp(side), -beta, -alpha)
            if score >= beta then return beta end
            if score > alpha then alpha = score end
          end
        end
      end
    end
  end end

  return alpha
end

local function search(b, st, side, depth, alpha, beta, ply, pvMove)
  if stopSearch or isTimeUp() then return evaluate(b), nil end
  nodes = nodes + 1

  if depth == 0 then
    return quiescence(b, st, side, alpha, beta), nil
  end

  local key = hashBoard(b, side)
  local tte = TT[key]
  if tte and tte.depth >= depth then
    local s = tte.score
    if tte.flag == 0 then return s, tte.move end
    if tte.flag == -1 and s > alpha then alpha = s end
    if tte.flag == 1 and s < beta  then beta  = s end
    if alpha >= beta then return s, tte.move end
  end

  -- generate legal moves
  local moves = {}
  for r=1,8 do for c=1,8 do
    local p = b[r][c]
    if p ~= " " and colorOf(p)==side then
      local list = legalTargetsFor(b, r, c, st)
      for _,m in ipairs(list) do
        m.fromR, m.fromC = r, c
        m.depth = ply
        table.insert(moves, m)
      end
    end
  end end

  if #moves == 0 then
    -- checkmate or stalemate
    if inCheck(b, side) then
      return - (100000 - ply), nil -- mate distance scoring
    else
      return 0, nil -- stalemate
    end
  end

  moves = orderMoves(b, st, side, moves, pvMove)

  local bestScore = -INF
  local bestMove = nil
  local originalAlpha = alpha

  for i,m in ipairs(moves) do
    local sim = {}
    for k,v in pairs(m) do sim[k]=v end
    if m.promote and not sim.promoPiece then sim.promoPiece = "Q" end
    local nb, ns = applyMove(b, m.fromR, m.fromC, sim, st)

    local score = -search(nb, ns, opp(side), depth-1, -beta, -alpha, ply+1, nil)
    if score > bestScore then
      bestScore = score
      bestMove = m
      if score > alpha then
        alpha = score
        if alpha >= beta then
          -- store killer
          killers[ply] = killers[ply] or {}
          local mk = moveKey(m)
          killers[ply][2] = killers[ply][1]
          killers[ply][1] = mk
          break
        end
      end
    end
    if stopSearch then break end
  end

  -- store in TT
  local flag = 0
  if bestScore <= originalAlpha then flag = 1   -- upper bound (beta cut for opponent)
  elseif bestScore >= beta then flag = -1       -- lower bound
  end
  TT[key] = { depth = depth, score = bestScore, flag = flag, move = bestMove }

  return bestScore, bestMove
end

local function aiChooseMove(b, st, side, maxTimeMs, maxDepth)
  startTime = ms()
  timeLimit = maxTimeMs or 1000
  stopSearch = false
  nodes = 0

  local bestMove, bestScore = nil, -INF
  local lastPV = nil

  for d=1,(maxDepth or 5) do
    local score, move = search(b, st, side, d, -INF, INF, 0, lastPV)
    if stopSearch then break end
    if move then bestMove = move; bestScore = score; lastPV = move end
    if isTimeUp() then break end
  end
  -- print(("AI depth reached, nodes=%d, best=%.1f"):format(nodes, bestScore))
  return bestMove
end

function love.update(dt)
  if gameOver or promoting then return end
  if AI_ENABLED and turn == AI_SIDE then
    -- compute synchronously; for longer times consider coroutine/yielding
    local move = aiChooseMove(board, state, AI_SIDE, AI_TIME_MS, AI_MAX_DEPTH)
    if move then
      -- Promotions from search default to queen; works fine
      board, state = applyMove(board, move.fromR, move.fromC, move, state)
      turn = (turn=="white") and "black" or "white"
      updateStatus()
    else
      -- no move (should be game over), but just in case:
      updateStatus()
    end
  end
end

