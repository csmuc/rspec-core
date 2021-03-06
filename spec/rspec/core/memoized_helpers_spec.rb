require 'spec_helper'

module RSpec::Core
  describe MemoizedHelpers do
    before(:each) { RSpec.configuration.configure_expectation_framework }

    def subject_value_for(describe_arg, &block)
      group = ExampleGroup.describe(describe_arg, &block)
      subject_value = nil
      group.example { subject_value = subject }
      group.run
      subject_value
    end

    describe "implicit subject" do
      describe "with a class" do
        it "returns an instance of the class" do
          expect(subject_value_for(Array)).to eq([])
        end
      end

      describe "with a Module" do
        it "returns the Module" do
          expect(subject_value_for(Enumerable)).to eq(Enumerable)
        end
      end

      describe "with a string" do
        it "returns the string" do
          expect(subject_value_for("Foo")).to eq("Foo")
        end
      end

      describe "with a number" do
        it "returns the number" do
          expect(subject_value_for(15)).to eq(15)
        end
      end

      it "can be overriden and super'd to from a nested group" do
        outer_subject_value = inner_subject_value = nil

        ExampleGroup.describe(Array) do
          subject { super() << :parent_group }
          example { outer_subject_value = subject }

          context "nested" do
            subject { super() << :child_group }
            example { inner_subject_value = subject }
          end
        end.run

        expect(outer_subject_value).to eq([:parent_group])
        expect(inner_subject_value).to eq([:parent_group, :child_group])
      end
    end

    describe "explicit subject" do
      [false, nil].each do |falsy_value|
        context "with a value of #{falsy_value.inspect}" do
          it "is evaluated once per example" do
            group = ExampleGroup.describe(Array)
            group.before do
              Object.should_receive(:this_question?).once.and_return(falsy_value)
            end
            group.subject do
              Object.this_question?
            end
            group.example do
              subject
              subject
            end
            expect(group.run).to be_true, "expected subject block to be evaluated only once"
          end
        end
      end

      describe "defined in a top level group" do
        it "replaces the implicit subject in that group" do
          subject_value = subject_value_for(Array) do
            subject { [1, 2, 3] }
          end
          expect(subject_value).to eq([1, 2, 3])
        end
      end

      describe "defined in a top level group" do
        let(:group) do
          ExampleGroup.describe do
            subject{ [4, 5, 6] }
          end
        end

        it "is available in a nested group (subclass)" do
          subject_value = nil
          group.describe("I'm nested!") do
            example { subject_value = subject }
          end.run

          expect(subject_value).to eq([4, 5, 6])
        end

        it "is available in a doubly nested group (subclass)" do
          subject_value = nil
          group.describe("Nesting level 1") do
            describe("Nesting level 2") do
              example { subject_value = subject }
            end
          end.run

          expect(subject_value).to eq([4, 5, 6])
        end

        it "can be overriden and super'd to from a nested group" do
          subject_value = nil
          group.describe("Nested") do
            subject { super() + [:override] }
            example { subject_value = subject }
          end.run

          expect(subject_value).to eq([4, 5, 6, :override])
        end
      end

      describe "with a name" do
        it "defines a method that returns the memoized subject" do
          list_value_1 = list_value_2 = subject_value_1 = subject_value_2 = nil

          ExampleGroup.describe do
            subject(:list) { [1, 2, 3] }
            example do
              list_value_1 = list
              list_value_2 = list
              subject_value_1 = subject
              subject_value_2 = subject
            end
          end.run

          expect(list_value_1).to eq([1, 2, 3])
          expect(list_value_1).to equal(list_value_2)

          expect(subject_value_1).to equal(subject_value_2)
          expect(subject_value_1).to equal(list_value_1)
        end

        it "is referred from inside subject by the name" do
          inner_subject_value = nil

          ExampleGroup.describe do
            subject(:list) { [1, 2, 3] }
            describe 'first' do
              subject(:first_element) { list.first }
              example { inner_subject_value = subject }
            end
          end.run

          expect(inner_subject_value).to eq(1)
        end

        context 'when `super` is used' do
          it "delegates to the parent context's `subject`, not the named mehtod" do
            inner_subject_value = nil

            ExampleGroup.describe do
              let(:list) { ["a", "b", "c"] }
              subject { [1, 2, 3] }

              describe 'first' do
                subject(:list) { super().first(2) }
                example { inner_subject_value = subject }
              end
            end.run

            expect(inner_subject_value).to eq([1, 2])
          end
        end
      end
    end

    context "using 'self' as an explicit subject" do
      it "delegates matcher to the ExampleGroup" do
        group = ExampleGroup.describe("group") do
          subject { self }
          def ok?; true; end
          def not_ok?; false; end

          it { should eq(self) }
          it { should be_ok }
          it { should_not be_not_ok }
        end

        expect(group.run).to be_true
      end
    end

    describe "#its" do
      subject do
        Class.new do
          def initialize
            @call_count = 0
          end

          def call_count
            @call_count += 1
          end
        end.new
      end

      context "with a call counter" do
        its(:call_count) { should eq(1) }
      end

      context "with nil value" do
        subject do
          Class.new do
            def nil_value
              nil
            end
          end.new
        end
        its(:nil_value) { should be_nil }
      end

      context "with nested attributes" do
        subject do
          Class.new do
            def name
              "John"
            end
          end.new
        end
        its("name")            { should eq("John") }
        its("name.size")       { should eq(4) }
        its("name.size.class") { should eq(Fixnum) }
      end

      context "when it responds to #[]" do
        subject do
          Class.new do
            def [](*objects)
              objects.map do |object|
                "#{object.class}: #{object.to_s}"
              end.join("; ")
            end

            def name
              "George"
            end
          end.new
        end
        its([:a]) { should eq("Symbol: a") }
        its(['a']) { should eq("String: a") }
        its([:b, 'c', 4]) { should eq("Symbol: b; String: c; Fixnum: 4") }
        its(:name) { should eq("George") }
        context "when referring to an attribute without the proper array syntax" do
          context "it raises an error" do
            its(:age) do
              expect do
                should eq(64)
              end.to raise_error(NoMethodError)
            end
          end
        end
      end

      context "when it does not respond to #[]" do
        subject { Object.new }

        context "it raises an error" do
          its([:a]) do
            expect do
              should eq("Symbol: a")
            end.to raise_error(NoMethodError)
          end
        end
      end

      context "calling and overriding super" do
        it "calls to the subject defined in the parent group" do
          group = ExampleGroup.describe(Array) do
            subject { [1, 'a'] }

            its(:last) { should eq("a") }

            describe '.first' do
              def subject; super().first; end

              its(:next) { should eq(2) }
            end
          end

          expect(group.run).to be_true
        end
      end

      context "with nil subject" do
        subject do
          Class.new do
            def initialize
              @counter = -1
            end
            def nil_if_first_time
              @counter += 1
              @counter == 0 ? nil : true
            end
          end.new
        end
        its(:nil_if_first_time) { should be(nil) }
      end

      context "with false subject" do
        subject do
          Class.new do
            def initialize
              @counter = -1
            end
            def false_if_first_time
              @counter += 1
              @counter > 0
            end
          end.new
        end
        its(:false_if_first_time) { should be(false) }
      end

      describe 'accessing `subject` in `before` and `let`' do
        subject { 'my subject' }
        before { @subject_in_before = subject }
        let(:subject_in_let) { subject }
        let!(:eager_loaded_subject_in_let) { subject }

        # These examples read weird, because we're actually
        # specifying the behaviour of `its` itself
        its(nil) { expect(subject).to eq('my subject') }
        its(nil) { expect(@subject_in_before).to eq('my subject') }
        its(nil) { expect(subject_in_let).to eq('my subject') }
        its(nil) { expect(eager_loaded_subject_in_let).to eq('my subject') }
      end
    end

    describe '#subject!' do
      let(:prepared_array) { [1,2,3] }
      subject! { prepared_array.pop }

      it "evaluates subject before example" do
        expect(prepared_array).to eq([1,2])
      end

      it "returns memoized value from first invocation" do
        expect(subject).to eq(3)
      end
    end
  end

  describe "#let" do
    let(:counter) do
      Class.new do
        def initialize
          @count = 0
        end
        def count
          @count += 1
        end
      end.new
    end

    let(:nil_value) do
      @nil_value_count += 1
      nil
    end

    it "generates an instance method" do
      expect(counter.count).to eq(1)
    end

    it "caches the value" do
      expect(counter.count).to eq(1)
      expect(counter.count).to eq(2)
    end

    it "caches a nil value" do
      @nil_value_count = 0
      nil_value
      nil_value

      expect(@nil_value_count).to eq(1)
    end

    let(:a_value) { "a string" }

    context 'when overriding let in a nested context' do
      let(:a_value) { super() + " (modified)" }

      it 'can use `super` to reference the parent context value' do
        expect(a_value).to eq("a string (modified)")
      end
    end

    context 'when the declaration uses `return`' do
      let(:value) do
        return :early_exit if @early_exit
        :late_exit
      end

      it 'can exit the let declaration early' do
        @early_exit = true
        expect(value).to eq(:early_exit)
      end

      it 'can get past a conditional `return` statement' do
        @early_exit = false
        expect(value).to eq(:late_exit)
      end
    end
  end

  describe "#let!" do
    subject { [1,2,3] }
    let!(:popped) { subject.pop }

    it "evaluates the value non-lazily" do
      expect(subject).to eq([1,2])
    end

    it "returns memoized value from first invocation" do
      expect(popped).to eq(3)
    end
  end

  describe 'using subject in before and let blocks' do
    shared_examples_for 'a subject' do
      let(:subject_id_in_let) { subject.object_id }
      before { @subject_id_in_before = subject.object_id }

      it 'should be memoized' do
        expect(subject_id_in_let).to eq(@subject_id_in_before)
      end

      it { should eq(subject) }
    end

    describe Object do
      context 'with implicit subject' do
        it_should_behave_like 'a subject'
      end

      context 'with explicit subject' do
        subject { Object.new }
        it_should_behave_like 'a subject'
      end

      context 'with a constant subject'do
        subject { 123 }
        it_should_behave_like 'a subject'
      end
    end
  end
end
