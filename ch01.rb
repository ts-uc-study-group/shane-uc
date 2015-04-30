Class.send(:alias_method, :λ, :define_method)
define_method(:elm) { |*args, &block|
  if args.empty?
    Class.new(&block)
  else
    Class.new(Struct.new(*args), &block)
  end.tap { |cls| cls.send(:define_method, :inspect) { self.to_s } }
}

Machine = elm(:stmt, :env) {
  λ(:step) { self.stmt, self.env = stmt.reduce(env) }
  λ(:run) {
    step while stmt.reducible?
    puts "#{stmt}, #{env}"
  }
}

Var = elm(:name) {
  λ(:to_s) { name.to_s }
  λ(:reducible?) { true }
  λ(:reduce) { |env| env[name] }
  λ(:evaluate) { |env| env[name] }
  λ(:to_ruby) { "-> e { e[#{name.inspect}] }" }
}

Noop = elm {
  λ(:to_s) { "noop" }
  λ(:==) { |stmt| stmt.instance_of?(Noop) }
  λ(:reducible?) { false }
  λ(:evaluate) { |env| env }
}

Assign = elm(:name, :exp) {
  λ(:to_s) { "#{name} = #{exp}" }
  λ(:reducible?) { true }
  λ(:reduce) { |env|
    if exp.reducible?
      [Assign.new(name, exp.reduce(env)), env]
    else
      [Noop.new, env.merge({name => exp})]
    end
  }
  λ(:evaluate) { |env|
    env.merge({name => exp.evaluate(env)})
  }
  λ(:to_ruby) {
    "-> e { e.merge({#{name.inspect} => (#{exp.to_ruby}).call(e)}) }"
  }
}

Seq = elm(:first, :second) {
  λ(:to_s) { "#{first}; #{second}" }
  λ(:reducible?) { true }
  λ(:reduce) { |env|
    case first
    when Noop.new
      [second, env]
    else
      reduced_fst, reduced_env = first.reduce(env)
      [Seq.new(reduced_fst, second), reduced_env]
    end
  }
  λ(:evaluate) { |env|
    second.evaluate(first.evaluate(env))
  }
  λ(:to_ruby) {
    "-> e { (#{second.to_ruby}).call((#{first.to_ruby}).call(e)) }"
  }
}

Num = elm(:val) {
  λ(:to_s) { val.to_s }
  λ(:reducible?) { false }
  λ(:evaluate) { |env| self }
  λ(:to_ruby) { "-> e { #{val.inspect} }" }
}

Bool = elm(:val) {
  λ(:to_s) { val.to_s }
  λ(:reducible?) { false }
  λ(:evaluate) { |env| self }
  λ(:to_ruby) { "-> e { #{val.inspect} }" }
}

Add = elm(:left, :right) {
  λ(:to_s) { "#{left} + #{right}" }
  λ(:reducible?) { true }
  λ(:reduce) { |env|
    if left.reducible?
      Add.new(left.reduce(env), right)
    elsif right.reducible?
      Add.new(left, right.reduce(env))
    else
      Num.new(left.val + right.val)
    end
  }
  λ(:evaluate) { |env|
    Num.new(left.evaluate(env).val + right.evaluate(env).val)
  }
  λ(:to_ruby) {
    "-> e { (#{left.to_ruby}).call(e) + (#{right.to_ruby}).call(e) }"
  }
}

Mul = elm(:left, :right) {
  λ(:to_s) { "#{left} * #{right}" }
  λ(:reducible?) { true }
  λ(:reduce) { |env|
    if left.reducible?
      Mul.new(left.reduce(env), right)
    elsif right.reducible?
      Mul.new(left, right.reduce(env))
    else
      Num.new(left.val * right.val)
    end
  }
  λ(:evaluate) { |env|
    Num.new(left.evaluate(env).val * right.evaluate(env).val)
  }
  λ(:to_ruby) {
    "-> e { (#{left.to_ruby}).call(e) * (#{right.to_ruby}).call(e) }"
  }
}

Lt = elm(:left, :right) {
  λ(:to_s) { "#{left} < #{right}" }
  λ(:reducible?) { true }
  λ(:reduce) { |env|
    if left.reducible?
      Lt.new(left.reduce(env), right)
    elsif right.reducible?
      Lt.new(left, right.reduce(env))
    else
      Bool.new(left.val < right.val)
    end
  }
  λ(:evaluate) { |env|
    Bool.new(left.evaluate(env).val < right.evaluate(env).val)
  }
  λ(:to_ruby) {
    "-> e { (#{left.to_ruby}).call(e) < (#{right.to_ruby}).call(e) }"
  }
}

If = elm(:cond, :cons, :alt) {
  λ(:to_s) { "if #{cond} { #{cons} } else { #{alt} }" }
  λ(:reducible?) { true }
  λ(:reduce) { |env|
    if cond.reducible?
      [If.new(cond.reduce(env), cons, alt), env]
    else
      case cond
      when Bool.new(true)
        [cons, env]
      when Bool.new(false)
        [alt, env]
      end
    end
  }
  λ(:evaluate) { |env|
    case cond.evaluate(env)
    when Bool.new(true)
      cons.evaluate(env)
    when Bool.new(false)
      alt.evaluate(env)
    end
  }
  λ(:to_ruby) {
    "-> e { if (#{cond.to_ruby}).call(e) then (#{cons.to_ruby}).call(e) else (#{alt.to_ruby}).call(e) end }"
  }
}

While = elm(:cond, :body) {
  λ(:to_s) { "while (#{cond}) { #{body} }" }
  λ(:reducible?) { true }
  λ(:reduce) { |env|
    [If.new(cond, Seq.new(body, self), Noop.new), env]
  }
  λ(:evaluate) { |env|
    case cond.evaluate(env)
    when Bool.new(true)
      evaluate(body.evaluate(env))
    when Bool.new(false)
      env
    end
  }
  λ(:to_ruby) {
    "-> e { while (#{cond.to_ruby}).call(e); e = (#{body.to_ruby}).call(e); end; e }"
  }
}

if __FILE__ == $0
  Machine.new(
    Add.new(
      Mul.new(Num.new(1), Num.new(2)),
      Mul.new(Num.new(3), Num.new(4))
    ), {}
  ).run

  Machine.new(
    Lt.new(
      Num.new(5),
      Add.new(Num.new(2), Num.new(2))
    ), {}
  ).run

  Machine.new(
    Assign.new(
      :x, Add.new(Var.new(:x), Num.new(1))
    ), {x: Num.new(2)}
  ).run

  Machine.new(
    If.new(
      Var.new(:x),
      Assign.new(:y, Num.new(1)),
      Assign.new(:y, Num.new(2))
    ), {x: Bool.new(true) }
  ).run

  Machine.new(
    If.new(
      Var.new(:x),
      Assign.new(:y, Num.new(1)),
      Noop.new
    ), {x: Bool.new(false) }
  ).run

  Machine.new(
    Seq.new(
      Assign.new(:x, Add.new(Num.new(1), Num.new(1))),
      Assign.new(:y, Add.new(Var.new(:x), Num.new(3)))
    ), {}
  ).run

  Machine.new(
    While.new(
      Lt.new(Var.new(:x), Num.new(5)),
      Assign.new(:x, Mul.new(Var.new(:x), Num.new(3)))
    ), {x: Num.new(1)}
  ).run

  stmt = Seq.new(
    Assign.new(:x, Add.new(Num.new(1), Num.new(1))),
    Assign.new(:y, Add.new(Var.new(:x), Num.new(3)))
  )
  puts stmt.evaluate({})

  stmt = While.new(
    Lt.new(Var.new(:x), Num.new(5)),
    Assign.new(:x, Mul.new(Var.new(:x), Num.new(3)))
  )
  puts stmt.evaluate({x: Num.new(1)})

  puts eval(Num.new(5).to_ruby).call({})
  puts eval(Bool.new(false).to_ruby).call({})
  puts eval(Var.new(:x).to_ruby).call({x: 7})
end
