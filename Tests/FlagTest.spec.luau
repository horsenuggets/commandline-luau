local Flag = require("../Source/Commandline/Flag")

return function()
	describe("Flag.new", function()
		it("should create a basic Flag with default values", function()
			local flag = Flag.new({ Name = "testflag" })
			expect(flag).to.be.ok()
			expect(flag.Name).to.equal("testflag")
			expect(flag.Description).to.equal("No description.")
			expect(flag.Type).to.equal(nil)
			expect(flag.Shorthand).to.equal(nil)
			expect(flag.Default).to.equal(nil)
		end)

		it("should create a Flag with custom description", function()
			local flag = Flag.new({
				Name = "verbose",
				Description = "Enable verbose output",
			})
			expect(flag.Description).to.equal("Enable verbose output")
		end)

		it("should create a Flag with shorthand", function()
			local flag = Flag.new({
				Name = "verbose",
				Shorthand = "v",
			})
			expect(flag.Shorthand).to.equal("v")
		end)

		it("should throw error if shorthand is not single character", function()
			expect(function()
				Flag.new({
					Name = "test",
					Shorthand = "ab",
				})
			end).to.throw()

			expect(function()
				Flag.new({
					Name = "test",
					Shorthand = "",
				})
			end).to.throw()
		end)

		it("should create a typed Flag with boolean type", function()
			local flag = Flag.new({
				Name = "enabled",
				Type = "boolean",
			})
			expect(flag.Type).to.equal("boolean")
		end)

		it("should create a typed Flag with int type", function()
			local flag = Flag.new({
				Name = "count",
				Type = "int",
			})
			expect(flag.Type).to.equal("int")
		end)

		it("should create a typed Flag with number type", function()
			local flag = Flag.new({
				Name = "value",
				Type = "number",
			})
			expect(flag.Type).to.equal("number")
		end)

		it("should create a typed Flag with string type", function()
			local flag = Flag.new({
				Name = "name",
				Type = "string",
			})
			expect(flag.Type).to.equal("string")
		end)

		it("should throw error for invalid type", function()
			expect(function()
				Flag.new({
					Name = "test",
					Type = "invalid",
				})
			end).to.throw()
		end)

		it("should create a typed Flag with default value", function()
			local flag = Flag.new({
				Name = "port",
				Type = "int",
				Default = 8080,
			})
			expect(flag.Type).to.equal("int")
			expect(flag.Default).to.equal(8080)
		end)

		it("should throw error when default value does not match type", function()
			expect(function()
				Flag.new({
					Name = "port",
					Type = "int",
					Default = "not a number",
				})
			end).to.throw()

			expect(function()
				Flag.new({
					Name = "enabled",
					Type = "boolean",
					Default = "true",
				})
			end).to.throw()

			expect(function()
				Flag.new({
					Name = "value",
					Type = "number",
					Default = "3.14",
				})
			end).to.throw()

			expect(function()
				Flag.new({
					Name = "name",
					Type = "string",
					Default = 123,
				})
			end).to.throw()
		end)

		it("should validate int type default value", function()
			local flag = Flag.new({
				Name = "count",
				Type = "int",
				Default = 5,
			})
			expect(flag.Default).to.equal(5)

			expect(function()
				Flag.new({
					Name = "count",
					Type = "int",
					Default = 3.14,
				})
			end).to.throw()
		end)

		it("should throw error for default value without type", function()
			expect(function()
				Flag.new({
					Name = "test",
					Default = "value",
				})
			end).to.throw()
		end)

		it("should allow nil default when no type is specified", function()
			local flag = Flag.new({
				Name = "test",
			})
			expect(flag.Default).to.equal(nil)
		end)

		it("should throw error for invalid Flag options", function()
			expect(function()
				Flag.new({ InvalidField = "test" })
			end).to.throw()

			expect(function()
				Flag.new("not a table")
			end).to.throw()
		end)

		it("should throw error when Name is missing", function()
			expect(function()
				Flag.new({
					Description = "Missing name",
				})
			end).to.throw()
		end)

		it("should create a complex Flag with all options", function()
			local flag = Flag.new({
				Name = "port",
				Description = "Server port number",
				Type = "int",
				Shorthand = "p",
				Default = 3000,
			})
			expect(flag.Name).to.equal("port")
			expect(flag.Description).to.equal("Server port number")
			expect(flag.Type).to.equal("int")
			expect(flag.Shorthand).to.equal("p")
			expect(flag.Default).to.equal(3000)
		end)
	end)
end
