local Arg = require("../Source/Commandline/Arg")

return function()
	describe("Arg.new", function()
		it("should create a basic Arg with default values", function()
			local arg = Arg.new({ Name = "testarg" })
			expect(arg).to.be.ok()
			expect(arg.Name).to.equal("testarg")
			expect(arg.Description).to.equal("No description.")
			expect(arg.Type).to.equal("string")
			expect(arg.Required).to.equal(true)
			expect(arg.Default).to.equal(nil)
		end)

		it("should create an Arg with custom description", function()
			local arg = Arg.new({
				Name = "testarg",
				Description = "A test argument",
			})
			expect(arg.Description).to.equal("A test argument")
		end)

		it("should create an Arg with different types", function()
			local boolArg = Arg.new({ Name = "flag", Type = "boolean" })
			expect(boolArg.Type).to.equal("boolean")

			local intArg = Arg.new({ Name = "count", Type = "int" })
			expect(intArg.Type).to.equal("int")

			local numArg = Arg.new({ Name = "value", Type = "number" })
			expect(numArg.Type).to.equal("number")

			local strArg = Arg.new({ Name = "text", Type = "string" })
			expect(strArg.Type).to.equal("string")
		end)

		it("should create an optional Arg when Required is false", function()
			local arg = Arg.new({
				Name = "optional",
				Required = false,
			})
			expect(arg.Required).to.equal(false)
		end)

		it("should create an Arg with default value and make it optional", function()
			local arg = Arg.new({
				Name = "count",
				Type = "int",
				Required = false,
				Default = 10,
			})
			expect(arg.Required).to.equal(false)
			expect(arg.Default).to.equal(10)
		end)

		it("should throw error for invalid type", function()
			expect(function()
				Arg.new({
					Name = "test",
					Type = "invalid",
				})
			end).to.throw()
		end)

		it("should throw error when default value does not match type", function()
			expect(function()
				Arg.new({
					Name = "test",
					Type = "int",
					Required = false,
					Default = "not a number",
				})
			end).to.throw()
		end)

		it("should throw error for default value on required Arg", function()
			expect(function()
				Arg.new({
					Name = "test",
					Required = true,
					Default = "value",
				})
			end).to.throw()
		end)

		it("should validate int type default value", function()
			local arg = Arg.new({
				Name = "count",
				Type = "int",
				Required = false,
				Default = 5,
			})
			expect(arg.Default).to.equal(5)

			expect(function()
				Arg.new({
					Name = "count",
					Type = "int",
					Required = false,
					Default = 3.14,
				})
			end).to.throw()
		end)

		it("should validate boolean type default value", function()
			local arg = Arg.new({
				Name = "flag",
				Type = "boolean",
				Required = false,
				Default = true,
			})
			expect(arg.Default).to.equal(true)

			expect(function()
				Arg.new({
					Name = "flag",
					Type = "boolean",
					Required = false,
					Default = "true",
				})
			end).to.throw()
		end)

		it("should validate number type default value", function()
			local arg = Arg.new({
				Name = "value",
				Type = "number",
				Required = false,
				Default = 3.14,
			})
			expect(arg.Default).to.equal(3.14)

			expect(function()
				Arg.new({
					Name = "value",
					Type = "number",
					Required = false,
					Default = "3.14",
				})
			end).to.throw()
		end)

		it("should validate string type default value", function()
			local arg = Arg.new({
				Name = "text",
				Type = "string",
				Required = false,
				Default = "hello",
			})
			expect(arg.Default).to.equal("hello")

			expect(function()
				Arg.new({
					Name = "text",
					Type = "string",
					Required = false,
					Default = 123,
				})
			end).to.throw()
		end)

		it("should throw error for invalid Arg options", function()
			expect(function()
				Arg.new({ InvalidField = "test" })
			end).to.throw()

			expect(function()
				Arg.new("not a table")
			end).to.throw()
		end)

		it("should throw error when Name is missing", function()
			expect(function()
				Arg.new({
					Description = "Missing name",
				})
			end).to.throw()
		end)
	end)
end
