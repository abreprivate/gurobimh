# -*- coding: utf-8 -*-
# cython: boundscheck=False
# cython: nonecheck=False
# cython: wraparound=False
# cython: initializedcheck=False
# cython: language_level = 3
# Copyright 2015 Michael Helmling
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation

from numbers import Number
from cpython cimport array as c_array
from array import array
import sys
# somewhat ugly hack: attribute getters/setters use this special return value to indicate a python
# exception; saves us from having to return objects while still allowing error handling
DEF ERRORCODE = -987654321

__version__ = '2015.2'
__arrayCodeInt = b'i' if sys.version_info.major == 2 else 'i'  # workaround bytes/unicode issues
__arrayCodeDbl = b'd' if sys.version_info.major == 2 else 'd'  # in Py2/3


class GurobiError(Exception):
    """General exception class used by this library."""
    pass


#  we create one master environment used in all models
cdef GRBenv *masterEnv = NULL
cdef int error = GRBloadenv(&masterEnv, NULL)
if error:
    raise ImportError('{}\n'.format(GRBgeterrormsg(masterEnv)))


def read(fname):
    """Read model from file; *fname* may be bytes or unicode type."""
    cdef int error
    cdef GRBmodel *cModel
    cdef Model model
    error = GRBreadmodel(masterEnv, _chars(fname), &cModel)
    if error:
        raise GurobiError('Unable to read model from file: {}'.format(error))
    model = Model(_create=False)
    model.model = cModel
    for i in range(model.NumVars):
        model.vars.append(Var(model, i))
    for i in range(model.NumConstrs):
        model.constrs.append(Constr(model, i))
    return model


cpdef quicksum(iterable):
    """Create LinExpr consisting of the parts of *iterable*. Elements in the iterator must be either
    Var or LinExpr objects."""
    cdef LinExpr result = LinExpr()
    for element in iterable:
        LinExpr.addInplace(result, element)
    return result


cdef dict CallbackTypes = {}  # maps callback "what" constant to return type of Model.cbGet()


cdef class CallbackClass:
    """Singleton class for callback constants"""
    cdef:
        readonly int MIPNODE
        readonly int SIMPLEX

        readonly int MIPNODE_OBJBST
        readonly int SPX_OBJVAL
        #TODO: insert missing callback WHATs

    def __init__(self):
        self.MIPNODE = GRB_CB_MIPNODE
        self.SIMPLEX = GRB_CB_SIMPLEX

        self.MIPNODE_OBJBST = GRB_CB_MIPNODE_OBJBST
        self.SPX_OBJVAL = GRB_CB_SPX_OBJVAL
        CallbackTypes[self.MIPNODE_OBJBST] = float
        CallbackTypes[self.SPX_OBJVAL] = float



# === ATTRIBUTES AND PARAMETERS ===
#
# model attrs
#TODO: insert missing attributes and parameters
cdef list IntAttrs = ['NumConstrs', 'NumVars', 'ModelSense', 'IsMIP', 'NumNZs', 'NumIntVars', 'NumBinVars',
                      'NumPWLObjVars', 'SolCount', 'IterCount', 'BarIterCount', 'NodeCount']
cdef list StrAttrs = ['ModelName']
cdef list DblAttrs = ['ObjCon', 'Runtime']
cdef list CharAttrs = []
# var attrs
StrAttrs += ['VarName']
DblAttrs += ['LB', 'UB', 'Obj', 'Start']
CharAttrs += ['VType']
# constraint attrs
DblAttrs += ['RHS']
StrAttrs += ['ConstrName']
CharAttrs += ['Sense']
# solution attrs
IntAttrs += ['Status']
DblAttrs += ['ObjVal', 'MIPGap', 'IterCount', 'NodeCount']
# var attrs for current solution
DblAttrs += ['X', 'RC']
# constr attr for current solution
DblAttrs += ['Pi', 'Slack']

cdef set IntAttrsLower  = set(a.lower().encode('ascii') for a in IntAttrs)
cdef set DblAttrsLower  = set(a.lower().encode('ascii') for a in DblAttrs)
cdef set StrAttrsLower  = set(a.lower().encode('ascii') for a in StrAttrs)
cdef set CharAttrsLower = set(a.lower().encode('ascii') for a in CharAttrs)

class AttrConstClass:
    """Singleton class for attribute name constants"""
for attr in IntAttrs + StrAttrs + DblAttrs + CharAttrs:
    setattr(AttrConstClass, attr, attr)

# termination
cdef list IntParams = []
cdef list DblParams = ['Cutoff', 'IterationLimit', 'TimeLimit']
cdef list StrParams = []
# tolerances
DblParams += ['FeasibilityTol', 'IntFeasTol', 'MIPGap', 'MIPGapAbs', 'OptimalityTol']
# simplex
IntParams += ['Method']
# MIP
IntParams += ['MIPFocus', 'VarBranch']
# cuts
IntParams += ['CutPasses']
# other
IntParams += ['OutputFlag', 'PrePasses', 'Presolve', 'Threads', 'UpdateMode']
StrParams += ['LogFile']
DblParams += ['TuneTimeLimit']

cdef set IntParamsLower = set(a.lower().encode('ascii') for a in IntParams)
cdef set DblParamsLower = set(a.lower().encode('ascii') for a in DblParams)
cdef set StrParamsLower = set(a.lower().encode('ascii') for a in StrParams)


class ParamConstClass:
    """Singleton class for parameter name constants"""
    pass

for param in IntParams + StrParams + DblParams:
    setattr(ParamConstClass, attr, attr)


cdef class GRBcls:
    """Dummy class emulating gurobipy.GRB"""

    cdef:
        # variable types
        readonly char BINARY, CONTINUOUS, INTEGER, SEMICONT, SEMIINT
        # objective directions
        readonly int MAXIMIZE, MINIMIZE
        # status codes
        readonly int INFEASIBLE, OPTIMAL, INTERRUPTED, INF_OR_UNBD, UNBOUNDED, ITERATION_LIMIT
        readonly int LOADED, CUTOFF, TIME_LIMIT, SOLUTION_LIMIT, NUMERIC, SUBOPTIMAL, INPROGRESS
        # constraint senses
        readonly basestring LESS_EQUAL, EQUAL, GREATER_EQUAL
        readonly object Callback, callback, Param, param, Attr, attr, status
    # workaround: INFINITY class member clashes with gcc macro INFINITY
    property INFINITY:
        def __get__(self):
            return GRB_INFINITY

    def __init__(self):
        self.status = type(
            'StatusConstClass' if sys.version_info.major == 3 else b'StatusConstClass',
            (),
            {})
        self.BINARY = GRB_BINARY
        self.CONTINUOUS = GRB_CONTINUOUS
        self.INTEGER = GRB_INTEGER
        self.SEMICONT = GRB_SEMICONT
        self.SEMIINT = GRB_SEMIINT

        self.MAXIMIZE = GRB_MAXIMIZE
        self.MINIMIZE = GRB_MINIMIZE

        self.status.INFEASIBLE = self.INFEASIBLE = GRB_INFEASIBLE
        self.status.OPTIMAL = self.OPTIMAL = GRB_OPTIMAL
        self.status.INTERRUPTED = self.INTERRUPTED = GRB_INTERRUPTED
        self.status.INF_OR_UNBD = self.INF_OR_UNBD = GRB_INF_OR_UNBD
        self.status.UNBOUNDED = self.UNBOUNDED = GRB_UNBOUNDED
        self.status.ITERATION_LIMIT = self.ITERATION_LIMIT = GRB_ITERATION_LIMIT
        self.status.LOADED = self.LOADED = GRB_LOADED
        self.status.CUTOFF = self.CUTOFF = GRB_CUTOFF
        self.status.TIME_LIMIT = self.TIME_LIMIT = GRB_TIME_LIMIT
        self.status.SOLUTION_LIMIT = self.SOLUTION_LIMIT = GRB_SOLUTION_LIMIT
        self.status.NUMERIC = self.NUMERIC = GRB_NUMERIC
        self.status.SUBOPTIMAL = self.SUBOPTIMAL = GRB_SUBOPTIMAL
        self.status.INPROGRESS = self.INPROGRESS = GRB_INPROGRESS

        self.LESS_EQUAL = '<'
        self.EQUAL = '='
        self.GREATER_EQUAL = '>'

        self.callback = self.Callback = CallbackClass()
        self.Param = self.param = ParamConstClass
        self.Attr = self.attr = AttrConstClass

GRB = GRBcls()


cdef class gurobi:
    """Emulate gurobipy.gurobi."""
    @staticmethod
    def version():
        cdef int major, minor, tech
        GRBversion(&major, &minor, &tech)
        return major, minor, tech

    @staticmethod
    def platform():
        return GRBplatform()


cdef class VarOrConstr:
    """Super class vor Variables and Constants. Identified by their index and a pointer to the
    model object.
    """
    #TODO: model should be weak-referecned as in gurobipy

    def __cinit__(self, Model model, int index):
        self.model = model
        self.index = index
        self.attrs = {}

    def __getattr__(self, key):
        if key[0] == '_':
            try:
                return self.attrs[key]
            except KeyError:
                raise AttributeError(key)
        if self.index < 0:
            raise GurobiError('{} not yet added to the model'.format(self.__class__.__name__))
        return self.model.getElementAttr(_chars(key), self.index)

    def __setattr__(self, key, value):
        if key[0] == '_':
            self.attrs[key] = value
        elif self.index < 0:
            raise GurobiError('{} not yet added to the model'.format(self.__class__.__name__))
        else:
            self.model.setElementAttr(_chars(key), self.index, value)

    def __str__(self):
        ret = '<gurobimh.{} '.format(type(self).__name__)
        if self.index == -1:
            return ret + '*Awaiting Model Update*>'
        elif self.index == -2:
            return ret + '(Removed)>'
        elif self.index == -3:
            return ret +'*removed*>'
        else:
            return ret + '{}>'.format(self.VarName if isinstance(self, Var) else self.ConstrName)

    def __repr__(self):
        return str(self)


cdef class Var(VarOrConstr):

    def __add__(self, other):
        cdef LinExpr result = LinExpr(self)
        LinExpr.addInplace(result, other)
        return result

    def __sub__(self, other):
        cdef LinExpr result = LinExpr(self)
        LinExpr.subtractInplace(result, other)
        return result

    def __mul__(self, other):
        return LinExpr(other, self)

    # explicit getters for time-critical attributes (speedup avoiding __getattr__)
    property X:
        def __get__(self):
            return self.model.getElementDblAttr(b'X', self.index)

    def __richcmp__(self, other, int op):
        if op == 2: # __eq__
            return TempConstr(LinExpr(self), GRB_EQUAL, LinExpr(other))
        elif op == 1: # __leq__
            return TempConstr(LinExpr(self), GRB_LESS_EQUAL, LinExpr(other))
        elif op == 5: # __geq__
            return TempConstr(LinExpr(self), GRB_GREATER_EQUAL, LinExpr(other))
        raise NotImplementedError()


cdef class Constr(VarOrConstr):
    # explicit getters for time-critical attributes (speedup avoiding __getattr__)
    property Slack:
        def __get__(self):
            return self.model.getElementDblAttr(b'Slack', self.index)



cdef char* _chars(s):
    """Convert input string to bytes, no matter if *s* is unicode or bytestring"""
    if isinstance(s, unicode):
        # encode to the specific encoding used inside of the module
        s = (<unicode>s).encode('utf8')
    return s


cdef int callbackFunction(GRBmodel *model, void *cbdata, int where, void *userdata):
    """Used for GRBsetcallbackfunc to emulate gurobipy's behaviour"""
    cdef Model theModel = <Model>userdata
    theModel.cbData = cbdata
    theModel.cbWhere = where
    try:
        theModel.callbackFn(theModel, where)
    except KeyboardInterrupt:
        theModel.cbInterrupt = True
        theModel.terminate()
    except Exception as e:
        return GRB_ERROR_CALLBACK


cdef class Model:

    def __init__(self, name='', _create=True):
        self.attrs = {}
        self.vars = []
        self.constrs = []
        self.varsAddedSinceUpdate = []
        self.varsRemovedSinceUpdate = []
        self.constrsAddedSinceUpdate = []
        self.constrsRemovedSinceUpdate = []
        self.numRangesAddedSinceUpdate = 0
        self.varInds = array(__arrayCodeInt, [0]*25)
        self.varCoeffs = array(__arrayCodeDbl, [0]*25)
        self.needUpdate = False
        self.callbackFn = None
        self.linExpDct = {}
        if _create:
            self.error = GRBnewmodel(masterEnv, &self.model, _chars(name),
                                     0, NULL, NULL, NULL, NULL, NULL)
            if self.error:
                raise GurobiError('Error creating model: {}'.format(self.error))

    def setParam(self, param, value):
        cdef bytes lParam
        if isinstance(param, unicode):
            param = (<unicode>param).encode('utf8')
        lParam = param.lower()
        if lParam in DblParamsLower:
            self.error = GRBsetdblparam(GRBgetenv(self.model), lParam, <double>value)
        elif lParam in IntParamsLower:
            self.error = GRBsetintparam(GRBgetenv(self.model), lParam, <int>value)
        else:
            raise GurobiError('Parameter {} not implemented or unknown'.format(param))
        if self.error:
            raise GurobiError('Error setting parameter: {}'.format(self.error))


    def __setattr__(self, key, value):
        if key[0] == '_':
            self.attrs[key] = value
        else:
            lAttr = key.lower()
            if lAttr in StrAttrsLower:
                GRBsetstrattr(self.model, key, value)
            elif lAttr in IntAttrsLower:
                GRBsetintattr(self.model, key, value)
            else:
                raise AttributeError('Unknown model attribute: {}'.format(attr))

    def __getattr__(self, attr):
        cdef int intValue
        cdef double dblValue
        cdef bytes lAttr = _chars(attr).lower()
        if lAttr in IntAttrsLower:
            return self.getIntAttr(lAttr)
        elif lAttr in DblAttrsLower:
            return self.getDblAttr(lAttr)
        elif lAttr in StrAttrsLower:
            return self.getStrAttr(lAttr)
        elif attr[0] == '_':
            try:
                return self.attrs[attr]
            except KeyError:
                raise AttributeError('Unknown model attribute: {}'.format(attr))
        else:
            raise AttributeError('Unknown model attribute: {}'.format(attr))

    cpdef getAttr(self, char *attrname, objs=None):
        return [obj.__getattr__(attrname) for obj in objs]

    cdef int getIntAttr(self, char *attr) except ERRORCODE:
        cdef int value
        self.error = GRBgetintattr(self.model, attr, &value)
        if self.error:
            raise GurobiError('Error retrieving int attribute: {}'.format(self.error))
        return value

    cdef double getDblAttr(self, char *attr) except ERRORCODE:
        cdef double value
        self.error = GRBgetdblattr(self.model, attr, &value)
        if self.error:
            raise GurobiError('Error retrieving double attribute: {}'.format(self.error))
        return value

    cdef char* getStrAttr(self, char *attrname):
        cdef char* value
        self.error = GRBgetstrattr(self.model, attrname, &value)
        if self.error:
            raise GurobiError('Error retrieving str attribute: {}'.format(self.error))
        return value

    cdef double getElementDblAttr(self, char *attr, int element) except ERRORCODE:
        """Fast retrieval of double attributes."""
        cdef double value
        self.error = GRBgetdblattrelement(self.model, attr, element, &value)
        if self.error:
            raise GurobiError('Error retrieving int element attr: {}'.format(self.error))
        return value

    cdef int setElementDblAttr(self, char *attr, int element, double value) except -1:
        """Fast setting of double attributes."""
        self.error = GRBsetdblattrelement(self.model, attr, element, value)
        if self.error:
            raise GurobiError('Error retrieving int element attr: {}'.format(self.error))

    cdef getElementAttr(self, char *attr, int element):
        cdef int intValue
        cdef double dblValue
        cdef char *strValue
        cdef bytes lAttr = attr.lower()
        if lAttr in DblAttrsLower:
            self.error = GRBgetdblattrelement(self.model, lAttr, element, &dblValue)
            if self.error:
                raise GurobiError('Error retrieving dbl attr: {}'.format(self.error))
            return dblValue
        elif lAttr in IntAttrsLower:
            self.error = GRBgetintattrelement(self.model, lAttr, element, &intValue)
            if self.error:
                raise GurobiError('Error retrieving int attr: {}'.format(self.error))
            return intValue
        elif lAttr in StrAttrsLower:
            self.error = GRBgetstrattrelement(self.model, lAttr, element, &strValue)
            if self.error:
                raise GurobiError('Error retrieving str attr: {}'.format(self.error))
            return str(strValue)
        else:
            raise AttributeError(attr)

    cdef int setElementAttr(self, char *attr, int element, newValue) except -1:
        cdef bytes lAttr = attr.lower()
        if lAttr in StrAttrsLower:
            self.error = GRBsetstrattrelement(self.model, lAttr, element, <const char*>newValue)
            if self.error:
                raise GurobiError('Error setting str attr: {}'.format(self.error))
        elif lAttr in DblAttrsLower:
            self.error = GRBsetdblattrelement(self.model, lAttr, element, <double>newValue)
            if self.error:
                raise GurobiError('Error setting double attr: {}'.format(self.error))
        elif lAttr in CharAttrsLower:
            self.error = GRBsetcharattrelement(self.model, lAttr, element, <char>newValue)
            if self.error:
                raise GurobiError('Error setting char attr: {}'.format(self.error))
        else:
            raise AttributeError('Unknown attribute {}'.format(attr))

    # explicit getters for time-critical attributes (speedup avoiding __getattr__)
    property NumConstrs:
        def __get__(self):
            return self.getIntAttr(b'numconstrs')

    cdef int fastGetX(self, int start, int length, double[::1] values) except -1:
        self.error = GRBgetdblattrarray(self.model, b'X', start, length, &values[0])
        if self.error:
            raise GurobiError('Error getting X: {}'.format(self.error))

    cpdef addVar(self, double lb=0, double ub=GRB_INFINITY, double obj=0.0,
               char vtype=GRB_CONTINUOUS, name='', column=None):
        cdef Var var
        cdef c_array.array[int] vind
        cdef c_array.array[double] vval
        if isinstance(name, unicode):
            name = name.encode('utf8')
        if column is None:
            self.error = GRBaddvar(self.model, 0, NULL, NULL, obj, lb, ub, vtype, name)
        else:
            vind = array(__arrayCodeInt, [(<Constr>constr).index for constr in (<Column>column).constrs])
            vval = array(__arrayCodeDbl, (<Column>column).coeffs)
            self.error = GRBaddvar(self.model, (<Column>column).numnz, vind.data.as_ints, vval.data.as_doubles, obj, lb, ub, vtype, name)
        if self.error:
            raise GurobiError('Error creating variable: {}'.format(self.error))
        var = Var(self, -1)
        self.varsAddedSinceUpdate.append(var)
        self.needUpdate = True
        return var

    cdef int compressLinExpr(self, LinExpr expr) except -1:
        """Compresses linear expressions by adding up coefficients of variables appearing more than
        once. The resulting compressed expression is stored in self.varInds / self.varCoeffs.
        :returns: Length of compressed expression
        """
        cdef int i, j, lenDct
        cdef double coeff
        cdef Var var
        cdef c_array.array[int] varInds
        cdef c_array.array[double] varCoeffs
        self.linExpDct.clear()
        for i in range(expr.length):
            var = <Var>expr.vars[i]
            if var.index < 0:
                raise GurobiError('Variable not in model')
            if var.index in self.linExpDct:
                self.linExpDct[var.index] += expr.coeffs.data.as_doubles[i]
            else:
                self.linExpDct[var.index] = expr.coeffs.data.as_doubles[i]
        lenDct = len(self.linExpDct)
        if len(self.varInds) < lenDct:
            c_array.resize(self.varInds, lenDct)
            c_array.resize(self.varCoeffs, lenDct)
        c_array.zero(self.varCoeffs)
        varInds = self.varInds
        varCoeffs = self.varCoeffs

        for i, (j, coeff) in enumerate(self.linExpDct.items()):
            varInds[i] = j
            varCoeffs[i] = coeff
        return lenDct

    cpdef addRange(self, LinExpr expr, double lower, double upper, name=''):
        cdef int lenDct = self.compressLinExpr(expr)
        self.error = GRBaddrangeconstr(self.model, lenDct, self.varInds.data.as_ints,
                                       self.varCoeffs.data.as_doubles, lower, upper,
                                       _chars(name))
        if self.error:
            raise GurobiError('Error adding range constraint: {}'.format(self.error))
        constr = Constr(self, -1)
        self.constrsAddedSinceUpdate.append(constr)
        self.numRangesAddedSinceUpdate += 1
        self.needUpdate = True
        return constr

    cpdef addConstr(self, lhs, basestring sense=None, rhs=None, name=''):
        cdef LinExpr expr
        cdef int lenDct
        cdef Constr constr
        cdef char my_sense
        if isinstance(lhs, TempConstr):
            expr = (<TempConstr>lhs).lhs - (<TempConstr>lhs).rhs
            if name == '' and sense is not None:
                name = sense
            my_sense = (<TempConstr>lhs).sense
        else:
            expr = LinExpr(lhs)
            LinExpr.subtractInplace(expr, rhs)
            my_sense = ord(sense[0])
        lenDct = self.compressLinExpr(expr)
        self.error = GRBaddconstr(self.model, lenDct, self.varInds.data.as_ints,
                                  self.varCoeffs.data.as_doubles, my_sense,
                                  -expr.constant, _chars(name))
        if self.error:
            raise GurobiError('Error adding constraint: {}'.format(self.error))
        constr = Constr(self, -1)
        self.constrsAddedSinceUpdate.append(constr)
        self.needUpdate = True
        return constr

    cdef Constr fastAddConstr(self, double[::1] coeffs, list vars, char sense, double rhs, name=''):
        """Efficiently add constraint circumventing LinExpr generation. *coeffs* and *vars* must
        have the same size (this is not checked!).

        Note: if there are duplicates in *vars*, an error will be thrown.
        """
        cdef int[:] varInds = self.varInds
        cdef int i
        cdef Constr constr
        if len(self.varInds) < coeffs.size:
            c_array.resize(self.varInds, coeffs.size)
            c_array.resize(self.varCoeffs, coeffs.size)
            varInds = self.varInds
        for i in range(coeffs.size):
            varInds[i] = (<Var>vars[i]).index
        self.error = GRBaddconstr(self.model, coeffs.size, &varInds[0],
                                  &coeffs[0], sense, rhs, _chars(name))
        if self.error:
            raise GurobiError('Error adding constraint: {}'.format(self.error))
        constr = Constr(self, -1)
        self.constrsAddedSinceUpdate.append(constr)
        self.needUpdate = True
        return constr

    cdef Constr fastAddConstr2(self, double[::1] coeffs, int[::1] varInds, char sense, double rhs, name=''):
        """Even faster constraint adding given variable index array. You need to ensure that
        *coeffs* and *varInds* have the same length, otherwise segfaults are likely to occur.
        """
        cdef Constr constr = Constr(self, -1)
        self.error = GRBaddconstr(self.model, coeffs.size, &varInds[0],
                                  &coeffs[0], sense, rhs, _chars(name))
        if self.error:
            raise GurobiError('Error adding constraint: {}'.format(self.error))
        self.constrsAddedSinceUpdate.append(constr)
        self.needUpdate = True
        return constr

    cpdef setObjective(self, expression, sense=None):
        cdef LinExpr expr = expression if isinstance(expression, LinExpr) else LinExpr(expression)
        cdef int i, error, length
        cdef Var var
        cdef c_array.array[double] zeros = array(__arrayCodeDbl, [0]*len(self.vars))
        if sense is not None:
            self.error = GRBsetintattr(self.model, b'ModelSense', <int>sense)
            if self.error:
                raise GurobiError('Error setting objective sense: {}'.format(self.error))
        GRBsetdblattrarray(self.model, b'Obj', 0, len(self.vars), zeros.data.as_doubles)
        length = self.compressLinExpr(expr)
        for i in range(length):
            self.error = GRBsetdblattrelement(self.model, b'Obj',
                                              self.varInds.data.as_ints[i],
                                              self.varCoeffs.data.as_doubles[i])
            if self.error:
                raise GurobiError('Error setting objective coefficient: {}'.format(self.error))
        if expr.constant != 0:
            self.error = GRBsetdblattr(self.model, b'ObjCon', expr.constant)
            if self.error:
                raise GurobiError('Error setting objective constant: {}'.format(self.error))
        self.needUpdate = True

    cpdef setPWLObj(self, Var var, x, y):
        cdef int npoints = len(x)
        cdef c_array.array[double] _x
        cdef c_array.array[double] _y
        if len(x) != len(y):
            raise GurobiError("Arguments x and y must have the same length")
        _x = array(__arrayCodeDbl, x)
        _y = array(__arrayCodeDbl, y)
        self.error = GRBsetpwlobj(self.model, (<Var>var).index, npoints, _x.data.as_doubles, _y.data.as_doubles)
        if self.error:
            raise GurobiError('Error setting PWL objective: {}'.format(self.error))
        self.needUpdate = True

    cpdef LinExpr getObjective(self):
        cdef double[:] values
        cdef double constant
        values = array(__arrayCodeDbl, [0]*len(self.vars))
        self.error = GRBgetdblattrarray(self.model, b'Obj', 0, len(self.vars), &values[0])
        if self.error:
            raise GurobiError('Error getting objective: {}'.format(self.error))
        self.error = GRBgetdblattr(self.model, b'ObjCon', &constant)
        if self.error:
            raise GurobiError('Error getting objective: {}'.format(self.error))
        coeffs = []
        vars = []
        for i in range(len(self.vars)):
            if values[i] > 0:
                coeffs.append(values[i])
                vars.append(self.vars[i])
        return LinExpr(coeffs, vars) + constant

    cdef fastSetObjective(self, int start, int length, double[::1] coeffs):
        """Efficient objective function manipulation: sets the coefficients of all variables with
        indices in range(start, start+length) according to *coeffs*, which must at least be of the
        correct length (NOT CHECKED!).
        """
        self.error = GRBsetdblattrarray(self.model, b'Obj', start, length, &coeffs[0])
        if self.error:
            raise GurobiError('Error setting objective function: {}'.format(self.error))
        self.needUpdate = True

    cpdef getVars(self):
        return self.vars[:]

    cpdef getConstrs(self):
        return self.constrs[:]

    cpdef getVarByName(self, name):
        cdef int numP
        self.error = GRBgetvarbyname(self.model, _chars(name), &numP)
        if self.error:
            raise GurobiError('Error getting variable: {}'.format(self.error))
        return self.vars[numP]

    cpdef getConstrByName(self, name):
        cdef int numP
        self.error = GRBgetconstrbyname(self.model, _chars(name), &numP)
        if self.error:
            raise GurobiError('Error getting constraint: {}'.format(self.error))
        return self.constrs[numP]

    cpdef remove(self, VarOrConstr what):
        if what.model is not self:
            raise GurobiError('Item to be removed not in model')
        if what.index >= 0:
            if isinstance(what, Constr):
                self.error = GRBdelconstrs(self.model, 1, &what.index)
                if self.error != 0:
                    raise GurobiError('Error removing constraint: {}'.format(self.error))
                self.constrsRemovedSinceUpdate.append(what.index)
            else:
                self.error = GRBdelvars(self.model, 1, &what.index)
                if self.error:
                    raise GurobiError('Error removing variable: {}'.format(self.error))
                self.varsRemovedSinceUpdate.append(what.index)
            what.index = -2
            self.needUpdate = True

    cpdef reset(self):
        self.update()
        self.error = GRBresetmodel(self.model)
        if self.error:
            raise GurobiError('Error resetting model: {}'.format(self.error))

    cpdef update(self):
        cdef int numVars = self.NumVars, numConstrs = self.NumConstrs, i
        cdef VarOrConstr voc
        if not self.needUpdate:
            return
        error = GRBupdatemodel(self.model)
        if error:
            raise GurobiError('Error updating the model: {}'.format(self.error))

        for i in sorted(self.varsRemovedSinceUpdate, reverse=True):
            voc = <Var>self.vars[i]
            voc.index = -3
            del self.vars[i]
            for voc in self.vars[i:]:
                voc.index -= 1
            numVars -= 1
        self.varsRemovedSinceUpdate = []

        for i in sorted(self.constrsRemovedSinceUpdate, reverse=True):
            voc = <Constr>self.constrs[i]
            voc.index = -3
            del self.constrs[i]
            for voc in self.constrs[i:]:
                voc.index -= 1
            numConstrs -= 1
        self.constrsRemovedSinceUpdate = []

        for i in range(len(self.constrsAddedSinceUpdate)):
            voc = self.constrsAddedSinceUpdate[i]
            voc.index = numConstrs + i
            self.constrs.append(voc)
        self.constrsAddedSinceUpdate = []

        for i in range(self.numRangesAddedSinceUpdate):
            range_var = Var(self, numVars + i)
            self.vars.append(range_var)
        numVars += self.numRangesAddedSinceUpdate
        self.numRangesAddedSinceUpdate = 0

        for i in range(len(self.varsAddedSinceUpdate)):
            voc = self.varsAddedSinceUpdate[i]
            voc.index = numVars + i
            self.vars.append(voc)
        self.varsAddedSinceUpdate = []

        self.needUpdate = False

    cpdef optimize(self, callback=None):
        if callback is not None:
            self.error = GRBsetcallbackfunc(self.model, callbackFunction, <void*>self)
            if self.error:
                raise GurobiError('Error installing callback: {}'.format(self.error))
            self.callbackFn = callback
            self.cbInterrupt = False
        self.update()
        self.error = GRBoptimize(self.model)
        if self.error:
            raise GurobiError('Error optimizing model: {}'.format(self.error))
        if callback is not None:
            self.callbackFn = None
            self.error = GRBsetcallbackfunc(self.model, NULL, NULL)
            if self.error:
                raise GurobiError('Error unsetting callback: {}'.format(self.error))
        if self.cbInterrupt:
            raise KeyboardInterrupt()

    cpdef cbGet(self, int what):
        cdef int intResult
        cdef double dblResult = 0
        if what not in CallbackTypes:
            raise GurobiError('Unknown callback "what" requested: {}'.format(what))
        elif CallbackTypes[what] is int:
            self.error = GRBcbget(self.model, self.cbWhere, what, <void*> &intResult)
            if self.error:
                raise GurobiError('Error calling cbget: {}'.format(self.error))
            return intResult
        elif CallbackTypes[what] is float:
            self.error = GRBcbget(self.cbData, self.cbWhere, what, <void*> &dblResult)
            if self.error:
                raise GurobiError('Error calling cbget: {}'.format(self.error))
            return dblResult
        else:
            raise GurobiError()

    cpdef terminate(self):
        GRBterminate(self.model)

    cpdef write(self, filename):
        if isinstance(filename, unicode):
            filename = filename.encode('utf8')
        self.error = GRBwrite(self.model, filename)
        if self.error:
            raise GurobiError('Error writing model: {}'.format(self.error))

    def __dealloc__(self):
        GRBfreemodel(self.model)


cdef c_array.array dblOne = array(__arrayCodeDbl, [1])


cdef class Column:
    def __init__(self, coeffs, constrs):
        if hasattr(coeffs, '__iter__') and hasattr(constrs, '__iter__'):
            if len(coeffs) != len(constrs):
                raise GurobiError("Array lengths don't match")
            self.coeffs = array(__arrayCodeDbl, coeffs)
            self.constrs = constrs
        else:
            self.numnz = 1
            self.coeffs = array(__arrayCodeDbl, [coeffs])
            self.constrs = [constrs]


cdef class LinExpr:

    def __init__(self, arg1=0.0, arg2=None):
        """Variants for calling this constructor:

        Single argument:
        ----------------
          - single variable
          - single number
          - existing LinExpr object (will be copied)
          - list of (coeff, var) pairs
        Two arguments:
        --------------
          - var, coeff
          - list of coeffs, list of vars
        """
        cdef int i
        if arg2 is None:
            if isinstance(arg1, Var):
                self.constant = 0
                self.vars =[arg1]
                self.coeffs = c_array.copy(dblOne)
                self.length = 1
                return
            elif isinstance(arg1, Number):
                self.constant = float(arg1)
                self.coeffs = c_array.clone(dblOne, 0, False)
                self.vars = []
                self.length = 0
                return
            elif isinstance(arg1, LinExpr):
                self.vars = (<LinExpr>arg1).vars[:]
                self.coeffs = c_array.copy((<LinExpr>arg1).coeffs)
                self.constant = (<LinExpr>arg1).constant
                self.length = len(self.coeffs)
                return
            else:
                arg1, arg2 = zip(*arg1)
        if isinstance(arg2, Var):
            arg1, arg2 = arg2, arg1
        if isinstance(arg1, Var):
            self.vars = [arg1]
            self.coeffs = c_array.clone(dblOne, 1, False)
            self.coeffs.data.as_doubles[0] = arg2
            self.constant = 0
            self.length = 1
        else:
            self.length = len(arg1)
            self.coeffs = c_array.clone(dblOne, self.length, False)
            for i in range(self.length):
                self.coeffs.data.as_doubles[i] = arg1[i]
            self.vars = list(arg2)
            self.constant = 0

    cpdef int size(LinExpr self):
        return self.length

    cpdef double getCoeff(LinExpr self, int i):
        return self.coeffs[i]

    cpdef Var getVar(LinExpr self, int i):
        return self.vars[i]

    cpdef double getConstant(LinExpr self):
        return self.constant

    cpdef double getValue(LinExpr self):
        cdef double total = 0
        for i in range(self.length):
            total += self.coeffs[i]*self.vars[i].X
        return total

    @staticmethod
    cdef int addInplace(LinExpr first, other) except -1:
        cdef LinExpr _other
        if isinstance(other, LinExpr):
            _other = other
            first.constant += _other.constant
            if _other.size() > 0:
                first.vars += _other.vars
                c_array.extend(first.coeffs, _other.coeffs)
                first.length += _other.length
        elif isinstance(other, Var):
            first.vars.append(other)
            c_array.resize_smart(first.coeffs, len(first.coeffs) + 1)
            first.coeffs.data.as_doubles[len(first.coeffs)-1] = 1
            first.length += 1
        else:
            first.constant += <double>other

    @staticmethod
    cdef int subtractInplace(LinExpr first, other) except -1:
        cdef LinExpr _other
        cdef int origLen = len(first.coeffs)
        cdef int i
        if isinstance(other, LinExpr):
            _other = other
            first.constant -= _other.constant
            if _other.size() > 0:
                first.vars += _other.vars
                c_array.extend(first.coeffs, _other.coeffs)
                for i in range(origLen, len(first.coeffs)):
                    first.coeffs.data.as_doubles[i] *= -1
                first.length += _other.length
        elif isinstance(other, Var):
            first.vars.append(other)
            c_array.resize_smart(first.coeffs, len(first.coeffs) + 1)
            first.coeffs.data.as_doubles[len(first.coeffs) - 1] = -1
            first.length += 1
        else:
            first.constant -= <double>other

    @staticmethod
    cdef int multiplyInplace(LinExpr expr, double scalar) except -1:
        for i in range(len(expr.coeffs)):
            expr.coeffs.data.as_doubles[i] *= scalar

    cdef LinExpr copy(LinExpr self):
        cdef LinExpr result = LinExpr(self.constant)
        result.vars = self.vars[:]
        result.coeffs = c_array.copy(self.coeffs)
        result.length = self.length
        return result

    def __add__(self, other):
        cdef LinExpr result = LinExpr(self).copy()
        LinExpr.addInplace(result, other)
        return result

    def __sub__(self, other):
        cdef LinExpr result = LinExpr(self).copy()
        LinExpr.subtractInplace(result, other)
        return result

    def __isub__(LinExpr self, other):
        LinExpr.subtractInplace(self, other)
        return self

    def __iadd__(LinExpr self, other):
        LinExpr.addInplace(self, other)
        return self

    def __mul__(self, scalar):
        if isinstance(scalar, LinExpr):
            self, scalar = scalar, self
        cdef LinExpr result = (<LinExpr>self).copy()
        LinExpr.multiplyInplace(result, scalar)
        return result

    def __imul__(self, double scalar):
        LinExpr.multiplyInplace(self, float(scalar))
        return self

    def __neg__(self):
        LinExpr.multiplyInplace(self, -1)
        return self

    def __richcmp__(self, other, int op):
        if op == 2: # __eq__
            return TempConstr(self, GRB_EQUAL, LinExpr(other))
        elif op == 1: # __leq__
            return TempConstr(self, GRB_LESS_EQUAL, LinExpr(other))
        elif op == 5: # __geq__
            return TempConstr(self, GRB_GREATER_EQUAL, LinExpr(other))
        raise NotImplementedError()

    def __repr__(self):
        return ' + '.join('{}*{}'.format(c, v) for c, v in zip(self.coeffs, self.vars)) + ' + {}'.format(self.constant)

cdef class TempConstr:

    def __init__(self, lhs, char sense, rhs):
        self.lhs = lhs if isinstance(lhs, LinExpr) else LinExpr(lhs)
        self.rhs = rhs if isinstance(rhs, LinExpr) else LinExpr(rhs)
        self.sense = sense
