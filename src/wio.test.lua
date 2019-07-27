local function testFormatters(Reader)
    describe('bytes(n)', function()
        it('should return data if enough data', function()
            local reader = Reader('test/wio/bytes.bin')
            assert.are.equals(reader:bytes(4), 'MARC')
        end)

        it('should return data if just enough data', function()
            local reader = Reader('test/wio/bytes.bin')
            assert.are.equals(reader:bytes(7), 'MARCELO')
        end)
        
        it('should return nil if not enough data', function()
            local reader = Reader('test/wio/bytes.bin')
            assert.is_nil(reader:bytes(50))
        end)
    end)
    
    describe('string()', function()
        it('should return data up to terminator', function()
            local reader = Reader('test/wio/string.bin')
            assert.are.equals(reader:string(), 'MARCELO HOSSOMI')
        end)
        
        it('should return nil if no terminator', function()
            local reader = Reader('test/wio/bytes.bin')
            assert.is_nil(reader:string())
        end)
    end)

    describe('int()', function()
        it('should read little endian', function()
            local reader = Reader('test/wio/integer.bin')
            assert.are.equals(reader:int(), 1)
        end)

        it('should return nil if no more data', function()
            local reader = Reader('test/wio/empty.bin')
            assert.are.is_nil(reader:int())
        end)
    end)

    describe('short()', function()
        it('should read little endian', function()
            local reader = Reader('test/wio/short.bin')
            assert.are.equals(reader:short(), 1)
        end)

        it('should return nil if no more data', function()
            local reader = Reader('test/wio/empty.bin')
            assert.are.is_nil(reader:short())
        end)
    end)

    describe('real()', function()
        it('should read little endian', function()
            local reader = Reader('test/wio/real.bin')
            assert.is_true(math.abs(reader:real() - 1.23) < 1E-5)
        end)

        it('should return nil if no more data', function()
            local reader = Reader('test/wio/empty.bin')
            assert.are.is_nil(reader:real())
        end)
    end)
end

describe('WIO', function()
    local wio = require 'wio'
    local util = require 'util'

    describe('StringReader', function()

        testFormatters(function(path)
            local file = assert(io.open(path, 'rb'))
            return wio.StringReader(file:read('*all'))
        end)

        before_each(function()
            reader = wio.StringReader(util.hexToBin('4D415243454C4F20484F53534F4D49'))
        end)

        it('should start at 1', function()
            assert.are.equals(reader._cursor, 1)
        end)

        describe('nextBytes(n)', function()
            it('should return data and advance', function()
                assert.are.equals(reader:nextBytes(7), 'MARCELO')
                assert.are.equals(reader._cursor, 8)
            end)

            it('should return nil and not advance if not enough data', function()
                assert.is_nil(reader:nextBytes(666))
                assert.are.equals(reader._cursor, 1)
            end)
        end)

        describe('nextUntil(d)', function()
            it('should return data without delimiter and advance', function()
                assert.are.equals(reader:nextUntil(' '), 'MARCELO')
                assert.are.equals(reader._cursor, 9)
            end)

            it('should return data with delimiter and advance', function()
                assert.are.equals(reader:nextUntil(' ', {inclusive = true}), 'MARCELO ')
                assert.are.equals(reader._cursor, 9)
            end)

            it('should return nil and not advance if not found', function()
                assert.is_nil(reader:nextUntil('XABLAU'))
                assert.are.equals(reader._cursor, 1)
            end)
        end)
        
        describe('skip(n)', function()
            it('should advance', function()
                reader:skip(5)
                assert.are.equals(reader._cursor, 6)
            end)

            it('should stop at end', function()
                reader:skip(666)
                assert.are.equals(reader._cursor, 16)
            end)
        end)
    end)

    describe('FileReader', function()

        testFormatters(function(path)
            local file = assert(io.open(path, 'rb'))
            return wio.FileReader(file, 2)
        end)

        before_each(function()
            file = assert(io.open('test/wio/bytes.bin', 'rb'))
            reader = wio.FileReader(file, 2)
        end)

        it('should start at 1', function()
            assert.are.equals(reader._cursor, 1)
            assert.are.equals(file:seek(), 2)
        end)

        describe('nextBytes(n)', function()
            it('should return data and advance', function()
                assert.are.equals(reader:nextBytes(7), 'MARCELO')
                assert.are.equals(reader._cursor, 1)
                assert.are.equals(file:seek(), 8)
            end)

            it('should return nil and not advance if not enough data', function()
                assert.is_nil(reader:nextBytes(666))
                assert.are.equals(reader._cursor, 1)
                assert.are.equals(file:seek(), 2)
            end)
        end)

        describe('nextUntil(d)', function()
            it('should return data without delimiter and advance', function()
                assert.are.equals(reader:nextUntil(' '), 'MARCELO')
                assert.are.equals(reader._cursor, 3)
                assert.are.equals(file:seek(), 8)
            end)

            it('should return data with delimiter and advance', function()
                assert.are.equals(reader:nextUntil(' ', {inclusive = true}), 'MARCELO ')
                assert.are.equals(reader._cursor, 3)
                assert.are.equals(file:seek(), 8)
            end)

            it('should return nil and not advance if not found', function()
                assert.is_nil(reader:nextUntil('XABLAU'))
                assert.are.equals(reader._cursor, 1)
                assert.are.equals(file:seek(), 2)
            end)
        end)
        
        describe('skip(n)', function()
            it('should advance', function()
                reader:skip(5)
                assert.are.equals(reader._cursor, 1)
                assert.are.equals(file:seek(), 6)
            end)

            it('should stop at end', function()
                reader:skip(666)
                assert.are.equals(reader._cursor, 1)
                assert.are.equals(file:seek(), 15)
            end)
        end)
    end)
end)
