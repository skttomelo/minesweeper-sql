CREATE TABLE Grid

    (

     X INT NOT NULL,          — X coordinate

     Y INT NOT NULL,          — Y coordinate

     S INT NULL,              — Status, see the user defined function udf_S

     CONSTRAINT PK_Grid PRIMARY KEY (X ASC, Y ASC)

    )

CREATE TABLE Mine

    (

     X INT NOT NULL,          — X coordinate

     Y INT NOT NULL,          — Y coordinate

     CONSTRAINT PK_Mine PRIMARY KEY (X ASC, Y ASC)

    )

/* The setting table will only ever hold one record */

CREATE TABLE Settings

    (

     MaxX INT NOT NULL,       — Number of rows

     MaxY INT NOT NULL,       — Number of columns

     NumberOfMines INT NOT NULL

    )

/* Inserting some default values */

INSERT  INTO Settings
VALUES  (10, 10, 10)

GO

CREATE FUNCTION udf_S (@S INT)

RETURNS CHAR(1)

/* A user defined function for the visual representation of the status */AS
    BEGIN

        RETURN (CASE

                  WHEN @S = -100 THEN ‘F’       –Flagged

                  WHEN @S = -10 THEN ‘S’        –Safe

                  WHEN @S = -1 THEN ‘?’         –Unknown

                  WHEN @S = 0 THEN ”           –No mines in the vicinity

                  WHEN @S = 9 THEN ‘M’          –Exploded mine

                  ELSE CONVERT(CHAR(1),@S)

–Number of mines in the vicinity
            END

                  )

    END

GO

CREATE PROCEDURE p_Initialize

    (

     @MaxX INT = NULL,

     @MaxY INT = NULL,

     @NumberOfMines INT = NULL,

     @Seed INT = NULL

    )

/* Initializing the game by creating the grid and randomly dropping the mines. I included a @seed parameter to be able to create the same map multiple times. If you call the procedure without any parameters he’ll use the same as last game, except the seed naturally */
AS

    BEGIN

        UPDATE  Settings

        SET     MaxX = ISNULL(@MaxX, MaxX),

                MaxY = ISNULL(@MaxY, MaxY),

                NumberOfMines = ISNULL(@NumberOfMines, NumberOfMines)



        SELECT  @MaxX = MaxX,

                @MaxY = MaxY,

                @NumberOfMines = NumberOfMines

        FROM    Settings

        TRUNCATE TABLE Mine

        TRUNCATE TABLE Grid



        DECLARE @x INT

        DECLARE @y INT

/* Creating records to represent the squares of the grid */

        SET @x = 1
        WHILE @x <= @MaxX

            BEGIN

                SET @y = 1

                WHILE @y <= @MaxY

                    BEGIN

                        INSERT  INTO grid

                        VALUES  (@x, @y, -1)

                        SET @y = @y + 1

                    END

                SET @x = @x + 1

            END

/* Setting the seed if necessary */
        IF @seed IS NOT NULL
            SET @x = RAND(@seed)

/* Dropping mines, but never on the same square */

        WHILE @NumberOfMines > 0

            BEGIN

                SET @x = FLOOR(RAND() * @MaxX) + 1

                SET @y = FLOOR(RAND() * @MaxY) + 1



                IF (SELECT  COUNT(*)

                    FROM    mine

                    WHERE   x = @x

                            AND y = @y

                   ) = 0

                    BEGIN

                        INSERT  INTO Mine

                        VALUES  (@x, @y)

                        SET @NumberOfMines = @NumberOfMines – 1

                    END

            END

    END



 GO



CREATE PROCEDURE p_Draw

/* Using a bit of dynamic SQL to draw the grid */
AS

    BEGIN

        DECLARE @sql VARCHAR(MAX)

        SELECT  @sql = ISNULL(@sql + ‘, ‘ + CHAR(13) + CHAR(9), ‘SELECT ‘)

                + ‘MAX(CASE WHEN Y = ‘ + CONVERT(VARCHAR(3), y)

                + ‘ THEN dbo.udf_S(S) END) as [‘ + CONVERT(VARCHAR(3), y)

                + ‘]’

        FROM    grid

        GROUP BY y

        ORDER BY y

        SET @sql = @sql + CHAR(13) + ‘FROM GRID

      GROUP BY X

      ORDER BY X’



        –PRINT @sql  –Uncomment this to see the SQL statement generated

        EXEC (@sql)

    END

GO

CREATE PROCEDURE p_MarkSafeSquares

/* Mark all unexplored squares next to a square with no mines in the vicinity (a blank square) See procedure p_Explore */
AS

    UPDATE  grid

    SET     S = -10

    FROM    (SELECT g2.x,

                    g2.y

             FROM   grid g1

                    INNER JOIN grid g2 ON g1.x – g2.x BETWEEN -1 AND 1

                                          AND g1.y – g2.y BETWEEN -1 AND 1

             WHERE  g1.S = 0

                    AND g2.S = -1

            ) subset

    WHERE   subset.x = grid.X

            AND subset.y = grid.y

GO

CREATE PROCEDURE p_ExploreSafeSquares (@count INT OUTPUT)

/* Explore all squares marked as safe. See procedure p_Explore */
AS –First update all safe squares with mines in the vicinity

    UPDATE  Grid

    SET     S = MinesDetected

    FROM    (SELECT g.x,

                    g.y,

                    COUNT(*) AS MinesDetected

             FROM   Grid g

                    INNER JOIN Mine m ON g.x – m.x BETWEEN -1 AND 1

                                         AND g.y – m.y BETWEEN -1 AND 1

             WHERE  S = -10

             GROUP BY g.x,

                    g.y

            ) s1

    WHERE   s1.x = grid.x

            AND s1.y = grid.y



      –Determine if the procedure should be run again

    SELECT  @count = COUNT(*)

    FROM    grid

    WHERE   s = -10



      –Second, update all other safe squares to blank squares

    UPDATE  Grid

    SET     S = 0

    WHERE   S = -10



GO

CREATE PROCEDURE p_Explore (@x INT, @y INT)

/* Expore an unknown square */
AS

    BEGIN

        IF (SELECT  COUNT(*)

            FROM    Grid

            WHERE   @x = x

                    AND @y = y

                    AND S = -100

           ) = 0 –Check if a square is flagged

            IF (SELECT  COUNT(*)

                FROM    Mine

                WHERE   @x = x

                        AND @y = y

               ) = 0 –Check if there’s a mine

                BEGIN

                    DECLARE @count INT

                    SET @count = (SELECT    COUNT(*)

                                  FROM      (SELECT x,

                                                    y

                                             FROM   Mine

                                             WHERE  x – @x BETWEEN -1 AND 1

                                                    AND y – @y BETWEEN -1 AND 1

                                             GROUP BY x,

                                                    y

                                            ) subset

                                 )

–Count the number of mines in the vicinity

–Update the square to the number of mines in the vicinity

                    UPDATE  Grid

                    SET     S = @count

                    WHERE   x = @x

                            AND y = @y


/* Here’s where the fun starts! In another language you would probably use recursion to solve this square by square, but with a single update you can explore multiple squares that you know are safe. It’s probably possible to do this in a single update instead of the 3 sequential updates, but I’ll leave that up to someone else. */

                    DECLARE @BlankSquares INT

                    IF @count = 0

                        SET @BlankSquares = 1



                    WHILE @BlankSquares > 0

                        BEGIN

                            EXEC p_MarkSafeSquares

                            EXEC p_ExploreSafeSquares @BlankSquares OUTPUT

                        END

                END

            ELSE

                        –A mine was hit!

                UPDATE  Grid

                SET     S = 9

                WHERE   x = @x

                        AND y = @y

    END

GO

CREATE PROCEDURE p_GameState

/* Showing the gamestate */
AS

    BEGIN

        DECLARE @NumberOfMines INT

        DECLARE @MaxX INT

        DECLARE @MaxY INT



        SELECT  @NumberOfMines = NumberOfMines,

                @MaxX = MaxX,

                @MaxY = MaxY

        FROM    Settings



        DECLARE @SquaresExplored INT,

            @MinesExploded INT,

            @SquaresFlagged INT



        SELECT  @SquaresExplored = SUM(CASE WHEN S BETWEEN 0 AND 8 THEN 1

                                            ELSE 0

                                       END),

                @MinesExploded = SUM(CASE WHEN S = 9 THEN 1

                                          ELSE 0

                                     END),

                @SquaresFlagged = SUM(CASE WHEN S = -100 THEN 1

                                           ELSE 0

                                      END)

        FROM    Grid



        SELECT  @SquaresExplored AS SquaresExplored,

                @MinesExploded AS MinesExploded,

                @SquaresFlagged AS SquaresFlagged,

                @NumberOfMines AS NumberOfMines,

                @MaxX * @MaxY AS TotalSquares,

                CASE WHEN @MinesExploded > 0 THEN ‘You lost!’

                     WHEN @SquaresExplored + @NumberOfMines = @MaxX * @MaxY

                     THEN ‘You won!’

                     ELSE ‘Keep on playing!’

                END AS GameState

    END

GO

CREATE PROCEDURE p_flag (@X INT, @Y INT)

/* A procedure to flag/unflag an unknown square as suspect */
AS

    BEGIN

        UPDATE  Grid

        SET     S = CASE WHEN S = -1 THEN -100  –Flag when unknown

                         WHEN S = -100 THEN -1  –Unflag when flagged

                         ELSE S                             –Otherwise no change

                    END

        WHERE   @x = X

                AND @y = y



    END

GO

CREATE PROCEDURE E (@X INT, @Y INT)

/* A procedure with a very short name to play the game. E for Explore */
AS

    BEGIN

        EXEC p_Explore @X, @Y

        EXEC p_Draw

        EXEC p_GameState

    END

GO

CREATE PROCEDURE F (@X INT, @Y INT)

/* A procedure with a very short name to play the game. F for Flag */
AS

    BEGIN

        EXEC p_Flag @X, @Y

        EXEC p_Draw

        EXEC p_GameState

    END

GO

CREATE PROCEDURE p_Solve1

/* It’s quite easy to write SQL statements to help clear the minefield. This one flags the only non-explored square next to a 1. */
AS

    UPDATE  Grid

    SET     S = -100

    FROM    (SELECT

      DISTINCT      x2,

                    y2

             FROM   (SELECT x1,

                            y1,

                            MAX(x2) x2,

                            MAX(y2) y2

                     FROM   (SELECT g1.x AS x1,

                                    g1.y AS y1,

                                    g2.x AS x2,

                                    g2.y AS y2

                             FROM   grid g1

                                    INNER JOIN grid g2 ON g1.x – g2.X BETWEEN -1 AND 1

                                                          AND g1.y – g2.y BETWEEN -1 AND 1

                             WHERE  g1.S = 1

                                    AND g2.S IN (-1, -100)

                            ) s1

                     GROUP BY x1,

                            y1

                     HAVING COUNT(*) = 1

                    ) s2

            ) s3

    WHERE   grid.x = s3.x2

            AND grid.y = s3.y2

            AND grid.s = -1

GO

EXEC p_Initialize 10, 10, 10, 10

EXEC e 1, 1
--the rest of the solution to ‘p_Initialize 10, 10, 10, 10’

/*
EXEC e 7, 6
EXEC f 8, 3

EXEC e 8, 4

EXEC e 9, 3
EXEC f 10, 1

EXEC e 10, 2

EXEC e 10, 3

EXEC f 7, 5

EXEC e 8, 5

EXEC f 9, 5

EXEC e 5, 6

EXEC e 6, 6

EXEC f 4, 6

EXEC e 3, 6

EXEC f 2, 6

EXEC e 1, 6

EXEC e 6, 7

EXEC e 5, 7

EXEC e 4, 7

EXEC e 3, 7

EXEC e 3, 8

EXEC e 4, 8

EXEC f 2, 7

EXEC e 1, 7

EXEC f 10, 8

EXEC e 8, 7

EXEC e 9, 7

EXEC e 10, 7

EXEC f 7, 7

EXEC f 8, 6

EXEC e 10, 5

EXEC e 10, 6

EXEC e 9, 6

*/
--A bigger one

/*

EXEC p_Initialize 30, 30, 60, 10

exec e 1,1

*/

--A really big one, with only a few mines, to see how long it takes the ‘auto explore’ to clear the field. (about 32 sec on my PC)

/*

EXEC p_Initialize 50, 50, 10, 10

EXEC e 1,1

*/
