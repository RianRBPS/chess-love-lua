local squareSize = 80
local board = {}

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

function love.load()
    for r =1, 8 do
        board[r] = {}
        for c = 1,8 do
            board[r][c] = startpos[r][c]
        end
    end
    love.window.setMode(squareSize*8, squareSize*8)
    love.window.setTitle("Lua + LOVE chess")
end

function love.draw()
    for r=1,8 do
        for c=1,8 do
            -- alternate colors of the board
            if (r+c)%2==0 then
                love.graphics.setColor(0.9,0.9,0.9) -- WHITE
            else
                love.graphics.setColor(0.2,0.4,0.2) -- GREEN
            end
            love.graphics.rectangle("fill",(c-1)*squareSize,(r-1)*squareSize,squareSize,squareSize)

            -- draw piece letter
            local piece = board[r][c]
            if piece ~= " " then
                love.graphics.setColor(0,0,0)
                love.graphics.printf(piece, (c-1)*squareSize, (r-1)*squareSize + squareSize/3, squareSize, "center")
            end
        end
    end
end